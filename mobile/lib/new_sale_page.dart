import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'brand_loader.dart';
import 'data/local_database.dart';
import 'data/sync_repository.dart';

class NewSalePage extends StatefulWidget {
  const NewSalePage({
    super.key,
    required this.repo,
    this.stocked = false,
  });

  final SyncRepository repo;

  /// false = preorder sale (stock ignored, OMB-); true = stocked goods (stock
  /// checked and deducted, no shipping cost, OMBSTK-).
  final bool stocked;

  @override
  State<NewSalePage> createState() =>
      _NewSalePageState();
}

/// One product line on a sale. The same product can appear on several lines
/// (e.g. two colours of one case), each with its own quantity, price and variant.
/// Markup (as a percentage of cost) used to suggest a selling price for
/// STOCKED goods. Cheaper products carry a bigger markup:
///   cost 5,000 and below      -> 170%
///   cost 5,001 to 10,000      -> 150%
///   cost 10,001 and above     -> 100%
/// Returns null when the product has no usable cost.
int? stockMarkupPercent(double cost) {
  if (cost <= 0) return null;
  if (cost < 5001) return 170;
  if (cost < 10001) return 150;
  return 100;
}

/// Suggested price for ONE unit of a stocked product: cost plus its markup,
/// rounded to the nearest naira. Only a starting point — the seller can
/// change it per sale (e.g. to give a discount) and that edited price is
/// recorded for that sale alone; the product itself is never changed.
double? suggestedStockPrice(double cost) {
  final markup = stockMarkupPercent(cost);
  if (markup == null) return null;
  return (cost * (100 + markup) / 100).roundToDouble();
}

class _SaleLine {
  _SaleLine(this.product, {bool stocked = false}) {
    if (stocked) {
      final cost = double.tryParse('${product['cost'] ?? ''}');
      if (cost != null) {
        final savedMarkup = double.tryParse(
          '${product['markup_percent'] ?? ''}',
        );
        markup = savedMarkup != null && savedMarkup >= 0
            ? savedMarkup.round()
            : stockMarkupPercent(cost);
        suggestedPrice = markup == null
            ? null
            : (cost * (100 + markup!) / 100).roundToDouble();
        if (suggestedPrice != null) {
          price.text = suggestedPrice!.round().toString();
        }
      }
    }
  }

  final Map<String, dynamic> product;

  /// Suggested unit price and the markup it came from (stocked sales only).
  double? suggestedPrice;
  int? markup;
  final TextEditingController qty = TextEditingController(text: '1');
  final TextEditingController price = TextEditingController();
  final TextEditingController variant = TextEditingController();

  int get id => product['id'] as int;
  int get quantity => int.tryParse(qty.text.trim()) ?? 0;
  double get unitPrice => double.tryParse(price.text.trim()) ?? 0;
  double get lineTotal => quantity * unitPrice;

  void dispose() {
    qty.dispose();
    price.dispose();
    variant.dispose();
  }
}

class _NewSalePageState extends State<NewSalePage> {
  final name = TextEditingController();
  final phone = TextEditingController();
  final address = TextEditingController();
  final city = TextEditingController();
  final state = TextEditingController();
  final notes = TextEditingController();

  List<Map<String, dynamic>> products = [];
  final List<_SaleLine> lines = [];

  String payment = 'Paid';
  bool loading = true;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final db = await LocalDatabase.instance.db;

    final rows = await db.query(
      'products',
      where: widget.stocked ? 'stock>0' : null,
      orderBy: 'name ASC',
    );

    if (mounted) {
      setState(() {
        products = rows;
        loading = false;
      });
    }
  }

  @override
  void dispose() {
    for (final line in lines) {
      line.dispose();
    }

    for (final c in [name, phone, address, city, state, notes]) {
      c.dispose();
    }

    super.dispose();
  }

  /// Total quantity of one product across every line (stocked sales are
  /// limited by stock, and two lines of the same product share that stock).
  int usedQty(int productId, {_SaleLine? except}) {
    var total = 0;
    for (final line in lines) {
      if (line.id == productId && line != except) {
        total += line.quantity;
      }
    }
    return total;
  }

  double get saleTotal => lines.fold(0.0, (sum, line) => sum + line.lineTotal);

  Future<void> addProduct() async {
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ProductPickerSheet(
        products: products,
        stocked: widget.stocked,
      ),
    );

    if (picked == null || !mounted) return;

    setState(() => lines.add(_SaleLine(picked, stocked: widget.stocked)));
  }

  void removeLine(_SaleLine line) {
    setState(() => lines.remove(line));
    line.dispose();
  }

  void changeQty(_SaleLine line, int delta) {
    final next = line.quantity + delta;
    if (next < 1) return;

    if (widget.stocked) {
      final stock = line.product['stock'] as int? ?? 0;
      if (usedQty(line.id, except: line) + next > stock) return;
    }

    setState(() => line.qty.text = '$next');
  }

  void toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> save() async {
    if (lines.isEmpty) {
      toast('Add at least one product.');
      return;
    }

    final items = <Map<String, dynamic>>[];

    for (final line in lines) {
      final label = '${line.product['name']}';

      if (line.quantity <= 0) {
        toast('Enter a quantity of 1 or more for $label.');
        return;
      }

      final price = double.tryParse(line.price.text.trim());
      if (price == null || price < 0) {
        toast('Enter a valid price for $label.');
        return;
      }

      if (widget.stocked) {
        final stock = line.product['stock'] as int? ?? 0;
        if (usedQty(line.id) > stock) {
          toast('Not enough stock for $label (have $stock).');
          return;
        }
      }

      final variant = line.variant.text.trim();

      items.add({
        'product_id': line.id,
        'qty': line.quantity,
        'unit_price': price.toStringAsFixed(2),
        if (variant.isNotEmpty) 'variant_note': variant,
      });
    }

    setState(() => saving = true);

    try {
      String message;

      if (kIsWeb) {
        // No offline mode on web — create it for real, right now.
        await widget.repo.createSaleOnline(
          customerName: name.text,
          customerPhone: phone.text,
          customerAddress: address.text,
          customerCity: city.text,
          customerState: state.text,
          paymentStatus: payment,
          notes: notes.text,
          items: items,
          saleType: widget.stocked ? 'stock' : 'preorder',
        );
        message = 'Sale created.';
      } else {
        await widget.repo.saveSaleOffline(
          customerName: name.text,
          customerPhone: phone.text,
          customerAddress: address.text,
          customerCity: city.text,
          customerState: state.text,
          paymentStatus: payment,
          notes: notes.text,
          items: items,
          saleType: widget.stocked ? 'stock' : 'preorder',
        );

        // The sale is always written locally first (that's what makes the
        // app work offline at all) — but whether it then syncs immediately
        // depends on whether we're actually online right now. Check instead
        // of always claiming "offline", and try a real sync so the message
        // reflects what happened rather than a guess.
        final connectivityResult = await Connectivity().checkConnectivity();
        final isOnline = !connectivityResult.contains(ConnectivityResult.none);

        message = 'Sale saved — will sync once you\'re back online.';
        if (isOnline) {
          try {
            await widget.repo.syncOnce();
            message = 'Sale saved and synced.';
          } catch (_) {
            message = 'Sale saved — will sync shortly.';
          }
        }
      }

      if (mounted) {
        toast(message);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        toast(userFacingError(e));
      }
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }

  Widget buildLine(int index, _SaleLine line) {
    final stock = line.product['stock'] as int? ?? 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${index + 1}. ${line.product['name']}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  onPressed: () => removeLine(line),
                  icon: const Icon(Icons.close),
                  tooltip: 'Remove from sale',
                ),
              ],
            ),
            if (widget.stocked) Text('Stock: $stock'),
            const SizedBox(height: 8),
            TextField(
              controller: line.variant,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Variant (optional)',
                hintText: 'e.g. Red, Large',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  onPressed: () => changeQty(line, -1),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                SizedBox(
                  width: 64,
                  child: TextField(
                    controller: line.qty,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Qty',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => changeQty(line, 1),
                  icon: const Icon(Icons.add_circle_outline),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: line.price,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Unit price',
                      prefixText: '₦',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            if (line.lineTotal > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Line total: ₦${line.lineTotal.toStringAsFixed(2)}',
                  style: const TextStyle(color: Colors.grey),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(
            widget.stocked ? 'New Stock Sale' : 'New Preorder Sale',
          ),
        ),
        body: loading
            ? const Center(child: BrandLoader())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    color: widget.stocked
                        ? Colors.green.shade50
                        : Colors.amber.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        widget.stocked
                            ? 'Stocked goods: stock is checked and deducted. '
                                'No shipping cost — delivery is settled off record. '
                                'Sale ID starts with OMBSTK-.'
                            : 'Preorder goods: stock does not matter here. '
                                'Enter the quantity the customer requested.',
                        style: const TextStyle(color: Colors.black),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'Customer name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone (WhatsApp number)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: address,
                    decoration: const InputDecoration(
                      labelText: 'Address',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: city,
                          decoration: const InputDecoration(
                            labelText: 'City (optional)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: state,
                          decoration: const InputDecoration(
                            labelText: 'State',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: payment,
                    decoration: const InputDecoration(
                      labelText: 'Payment status',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Paid', child: Text('Paid')),
                      DropdownMenuItem(value: 'Pending', child: Text('Pending')),
                      DropdownMenuItem(value: 'Refunded', child: Text('Refunded')),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => payment = v);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    lines.isEmpty
                        ? 'Products'
                        : 'Products (${lines.length})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  for (var i = 0; i < lines.length; i++) buildLine(i, lines[i]),
                  if (lines.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'No products added yet.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: addProduct,
                    icon: const Icon(Icons.add),
                    label: Text(
                      lines.isEmpty ? 'Add product' : 'Add another product',
                    ),
                  ),
                  if (lines.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'Total: ₦${saleTotal.toStringAsFixed(2)}',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextField(
                    controller: notes,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Notes',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: saving ? null : save,
                    icon: const Icon(Icons.save),
                    label: Text(saving ? 'Saving...' : 'Save sale'),
                  ),
                ],
              ),
      );
}

/// Search-and-pick sheet for adding a product to a sale.
///
/// The search text lives in this widget's own State (not in a builder
/// closure), so when the keyboard opens/closes or the screen resizes the
/// list always matches what is typed. Otherwise the list can silently reset
/// to the full catalogue and a tap lands on a different product.
class _ProductPickerSheet extends StatefulWidget {
  const _ProductPickerSheet({
    required this.products,
    required this.stocked,
  });

  final List<Map<String, dynamic>> products;
  final bool stocked;

  @override
  State<_ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<_ProductPickerSheet> {
  final search = TextEditingController();

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = search.text.trim().toLowerCase();

    final matches = widget.products.where((p) {
      return '${p['name']}'.toLowerCase().contains(query);
    }).toList();

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: search,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Search products',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            Expanded(
              child: matches.isEmpty
                  ? const Center(child: Text('No matching products.'))
                  : ListView.builder(
                      itemCount: matches.length,
                      itemBuilder: (_, i) {
                        final product = matches[i];

                        return ListTile(
                          key: ValueKey(product['id']),
                          title: Text('${product['name']}'),
                          subtitle: widget.stocked
                              ? Text('Stock: ${product['stock']}')
                              : null,
                          onTap: () => Navigator.pop(context, product),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

