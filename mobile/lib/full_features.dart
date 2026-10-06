import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'brand_loader.dart';
import 'core/biometric_guard.dart';
import 'data/api_client.dart';
import 'core/network_errors.dart';
import 'data/app_session.dart';
import 'data/local_database.dart';
import 'data/sync_repository.dart';
import 'data/sale_kind.dart';
import 'invoice_actions.dart';
import 'journey_widgets.dart';
import 'chat_page.dart';
import 'new_sale_page.dart';
import 'profile_page.dart';

class WebsiteFeaturesPage extends StatefulWidget {
  const WebsiteFeaturesPage({
    super.key,
    required this.api,
    required this.local,
    required this.repo,
    required this.refreshKey,
  });

  final ApiClient api;
  final LocalDatabase local;
  final SyncRepository repo;
  final int refreshKey;

  @override
  State<WebsiteFeaturesPage> createState() => _WebsiteFeaturesPageState();
}

class _WebsiteFeaturesPageState extends State<WebsiteFeaturesPage> {
  String? error;

  @override
  void initState() {
    super.initState();
    // Refresh whenever this menu opens, so a role change takes effect
    // without needing to log out and back in.
    AppSession.refresh(widget.api).then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> open(Widget page) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
  }

  void _adminOnlySnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('That page is restricted to admins.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = AppSession.isAdmin;
    return Scaffold(
      appBar: AppBar(
        title: const Text('All Website Features'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Chip(
                label: Text(isAdmin ? 'Admin' : 'Staff'),
                avatar: Icon(isAdmin ? Icons.shield : Icons.person, size: 18),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (error != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.error_outline),
                title: const Text('Request error'),
                subtitle: Text(error!),
                trailing: IconButton(
                  onPressed: () => setState(() => error = null),
                  icon: const Icon(Icons.close),
                ),
              ),
            ),

          _tile(
            Icons.inventory_2,
            'Manage products',
            'Admin changes require biometric verification (stock adjustments remain routine).',
            () => open(WebProductsPage(api: widget.api)),
          ),

          _tile(
            Icons.receipt_long,
            'Manage sales',
            'Shipping settlement requires biometric verification.',
            () => open(WebSalesPage(api: widget.api, repo: widget.repo)),
          ),

          _tile(
            Icons.inventory,
            'Stock log',
            'Inventory and stock records',
            () => open(
              ReportPage(
                title: 'Inventory Report',
                type: 'inventory',
                load: widget.api.inventoryReport,
              ),
            ),
          ),

          _tile(
            Icons.local_shipping,
            'Shipment batches',
            'Create and manage batches; biometric verification is required when marking a batch arrived.',
            () => open(BatchesPage(api: widget.api, isAdmin: isAdmin)),
          ),

          _tile(
            Icons.timeline,
            'Order journey',
            'Move orders through fulfilled, CN transit and consolidation in bulk',
            () => open(JourneyPage(api: widget.api)),
          ),

          _tile(
            Icons.delivery_dining,
            'Deliveries',
            'Ready sales, consolidation, status and labels',
            () => open(DeliveriesPage(api: widget.api)),
          ),

          _tile(
            Icons.price_change,
            'Rates',
            'Courier and monthly rates — biometric verification is required for edits.',
            () => open(RatesPage(api: widget.api, isAdmin: isAdmin)),
          ),

          _tile(
            Icons.bar_chart,
            'Reports',
            'Sales, shipping and inventory reports',
            () => open(ReportsPage(api: widget.api)),
          ),

          _tile(
            Icons.settings,
            'Settings',
            isAdmin
                ? 'Business and label settings — biometric verification required to save'
                : 'Business and label settings — admins only',
            isAdmin
                ? () => open(SettingsPage(api: widget.api))
                : _adminOnlySnack,
            locked: !isAdmin,
          ),

          _tile(
            Icons.lock_reset,
            'My account',
            'Change your username or password',
            () => open(ProfilePage(api: widget.api)),
          ),

          _tile(
            Icons.forum_outlined,
            'Team chat',
            'Converse with the whole team, mention users with @, and reply to messages.',
            () => open(ChatPage(api: widget.api)),
          ),

          _tile(
            Icons.people,
            'Users',
            isAdmin
                ? 'Add or remove users — biometric verification required'
                : 'Add or remove users — admins only',
            isAdmin
                ? () => open(UsersPage(api: widget.api))
                : _adminOnlySnack,
            locked: !isAdmin,
          ),

          if (isAdmin)
            _tile(
              Icons.history,
              'Audit log',
              'Who changed what across the system',
              () => open(AuditLogPage(api: widget.api)),
            ),

          _tile(
            Icons.delete_sweep,
            'Clear test data',
            isAdmin
                ? 'Confirmation + biometric verification required'
                : 'Confirmation-protected test-data cleanup — admins only',
            isAdmin
                ? () => open(ClearDataPage(api: widget.api, local: widget.local))
                : _adminOnlySnack,
            locked: !isAdmin,
          ),
        ],
      ),
    );
  }

  Widget _tile(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap, {
    bool locked = false,
  }) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        trailing: Icon(locked ? Icons.lock_outline : Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class WebProductsPage extends StatefulWidget {
  const WebProductsPage({super.key, required this.api});

  final ApiClient api;

  @override
  State<WebProductsPage> createState() => _WebProductsPageState();
}

class _WebProductsPageState extends State<WebProductsPage> {
  List<dynamic> rows = [];
  bool busy = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      rows = await widget.api.products();
    } catch (_) {}

    if (mounted) {
      setState(() => busy = false);
    }
  }

  Future<void> form([Map<String, dynamic>? old]) async {
    final name = TextEditingController(text: '${old?['name'] ?? ''}');
    final sku = TextEditingController(text: '${old?['sku'] ?? ''}');
    final supplierCost = TextEditingController(
      text: '${old?['supplier_cost'] ?? old?['cost'] ?? ''}',
    );
    final landedCost = TextEditingController(
      text: '${old?['cost'] ?? ''}',
    );
    final markup = TextEditingController(
      text: '${old?['markup_percent'] ?? 0}',
    );
    final sellingPrice = TextEditingController(
      text: '${old?['selling_price'] ?? ''}',
    );
    final shippingCost = TextEditingController(
      text: '${old?['inbound_shipping_cost'] ?? 0}',
    );
    final length = TextEditingController(text: '${old?['length_cm'] ?? ''}');
    final width = TextEditingController(text: '${old?['width_cm'] ?? ''}');
    final height = TextEditingController(text: '${old?['height_cm'] ?? ''}');
    final weight = TextEditingController(text: '${old?['actual_weight_kg'] ?? ''}');
    final stock = TextEditingController(text: '${old?['stock'] ?? 0}');

    String shippingMode = 'sea';
    bool calculating = false;
    Map<String, dynamic>? costResult;

    try {
      final ok = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              Future<void> calculate() async {
                setDialogState(() => calculating = true);
                try {
                  final result = await widget.api.calculateProductCost(
                    cost: supplierCost.text,
                    lengthCm: length.text,
                    widthCm: width.text,
                    heightCm: height.text,
                    actualWeightKg: weight.text,
                    markupPercent: markup.text,
                    mode: shippingMode,
                  );
                  landedCost.text = '${result['landed_cost'] ?? 0}';
                  shippingCost.text = '${result['shipping_cost'] ?? 0}';
                  sellingPrice.text = '${result['selling_price'] ?? 0}';
                  costResult = result;
                  setDialogState(() {});
                } catch (e) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(content: Text(userFacingError(e))),
                    );
                  }
                } finally {
                  if (dialogContext.mounted) {
                    setDialogState(() => calculating = false);
                  }
                }
              }

              Widget row(String label, dynamic value, {bool bold = false}) {
                final display = value is num ? value.toStringAsFixed(2) : '${value}';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(child: Text(label)),
                      const SizedBox(width: 12),
                      Text(display, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
                    ],
                  ),
                );
              }

              return AlertDialog(
                title: Text(old == null ? 'New product' : 'Edit product'),
                content: SizedBox(
                  width: 480,
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
                        const SizedBox(height: 12),
                        TextField(controller: sku, decoration: const InputDecoration(labelText: 'SKU')),
                        const SizedBox(height: 12),
                        TextField(
                          controller: supplierCost,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Supplier cost'),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: markup,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Markup %'),
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          value: shippingMode,
                          decoration: const InputDecoration(labelText: 'Inbound shipping mode'),
                          items: const [
                            DropdownMenuItem(value: 'sea', child: Text('Sea')),
                            DropdownMenuItem(value: 'air', child: Text('Air')),
                          ],
                          onChanged: calculating
                              ? null
                              : (value) {
                                  if (value != null) {
                                    setDialogState(() => shippingMode = value);
                                  }
                                },
                        ),
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed: calculating ? null : calculate,
                          icon: calculating
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.calculate_rounded),
                          label: Text(calculating ? 'Calculating...' : 'Calculate true cost'),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: landedCost,
                          readOnly: true,
                          decoration: const InputDecoration(labelText: 'True landed cost / unit'),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: shippingCost,
                          readOnly: true,
                          decoration: const InputDecoration(labelText: 'Inbound shipping / unit'),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: sellingPrice,
                          readOnly: true,
                          decoration: const InputDecoration(labelText: 'Suggested selling price / unit'),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(child: TextField(controller: length, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Length cm'))),
                            const SizedBox(width: 8),
                            Expanded(child: TextField(controller: width, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Width cm'))),
                            const SizedBox(width: 8),
                            Expanded(child: TextField(controller: height, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Height cm'))),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: weight,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Actual weight kg'),
                        ),
                        if (costResult != null) ...[
                          const SizedBox(height: 12),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Financial breakdown', style: TextStyle(fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 8),
                                  row('Product / supplier cost', costResult!['supplier_cost']),
                                  row('Volume shipping', costResult!['volume_shipping_cost']),
                                  row('Weight + packaging', costResult!['weight_shipping_cost']),
                                  const Divider(),
                                  row('True landed cost', costResult!['landed_cost'], bold: true),
                                  row('Break-even price', costResult!['break_even_price'], bold: true),
                                  row('Markup', '${costResult!['markup_percent'] ?? 0}%'),
                                  row('Selling price', costResult!['selling_price'], bold: true),
                                  row('Gross profit / unit', costResult!['gross_profit'], bold: true),
                                  row('Gross margin', '${(costResult!['gross_margin_percent'] ?? 0).toStringAsFixed(2)}%', bold: true),
                                  row('Shipping mode', '${costResult!['mode']}'.toUpperCase()),
                                ],
                              ),
                            ),
                          ),
                        ],
                        if (old == null) ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: stock,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Opening stock'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(onPressed: calculating ? null : () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
                  FilledButton(onPressed: calculating ? null : () => Navigator.pop(dialogContext, true), child: const Text('Save')),
                ],
              );
            },
          );
        },
      );

      if (ok != true) return;

      if (name.text.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Product name is required.')),
          );
        }
        return;
      }

      if (landedCost.text.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Calculate the true landed cost before saving.'),
            ),
          );
        }
        return;
      }

      if (!await BiometricGuard.require(
        context,
        reason: old == null
            ? 'Verify your identity before creating a product.'
            : 'Verify your identity before changing product details.',
      )) {
        return;
      }

      final data = <String, dynamic>{
        'name': name.text.trim(),
        'sku': sku.text.trim().isEmpty ? null : sku.text.trim(),
        'cost': double.tryParse(landedCost.text.trim()) ?? 0,
        'supplier_cost': double.tryParse(supplierCost.text.trim()),
        'inbound_shipping_cost': double.tryParse(shippingCost.text.trim()),
        'markup_percent': double.tryParse(markup.text.trim()),
        'selling_price': double.tryParse(sellingPrice.text.trim()),
        'length_cm': double.tryParse(length.text.trim()),
        'width_cm': double.tryParse(width.text.trim()),
        'height_cm': double.tryParse(height.text.trim()),
        'actual_weight_kg': double.tryParse(weight.text.trim()),
      };

      if (old == null) {
        data['stock'] = int.tryParse(stock.text.trim()) ?? 0;
        await widget.api.createProduct(data);
      } else {
        await widget.api.updateProduct(old['id'] as int, data);
      }

      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(userFacingError(e))));
      }
    } finally {
      for (final controller in [
        name, sku, supplierCost, landedCost, markup, sellingPrice,
        shippingCost, length, width, height, weight, stock,
      ]) {
        controller.dispose();
      }
    }
  }

  Future<void> adjustStock(
    Map<String, dynamic> product,
  ) async {
    final quantity = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            'Adjust ${product['name']}',
          ),
          content: TextField(
            controller: quantity,
            keyboardType: const TextInputType.numberWithOptions(
              signed: true,
            ),
            decoration: const InputDecoration(
              labelText: 'Change quantity',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (ok != true) return;

    final change = int.tryParse(quantity.text.trim());

    if (change == null || change == 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Enter a non-zero whole number.',
            ),
          ),
        );
      }
      return;
    }

    try {
      await widget.api.stockAdjust({
        'product_id': product['id'],
        'change_qty': change,
        'reason': 'Mobile stock adjustment',
      });

      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userFacingError(e))),
        );
      }
    }
  }

  Future<void> deleteProduct(
    Map<String, dynamic> product,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete product'),
          content: Text(
            'Delete "${product['name']}"?',
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    if (!await BiometricGuard.require(
      context,
      reason: 'Verify your identity before deleting this product.',
    )) return;

    try {
      await widget.api.deleteProduct(
        product['id'] as int,
      );
      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userFacingError(e))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Products'),
        actions: [
          IconButton(
            onPressed: () => form(),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: busy
          ? const Center(
              child: BrandLoader(),
            )
          : RefreshIndicator(
              onRefresh: load,
              child: rows.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 160),
                        Center(
                          child: Text('No products found.'),
                        ),
                      ],
                    )
                  : ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (_, index) {
                        final product =
                            Map<String, dynamic>.from(
                          rows[index] as Map,
                        );

                        return Card(
                          child: ListTile(
                            title: Text(
                              '${product['name'] ?? ''}',
                            ),
                            subtitle: Text(
                              '${product['sku'] ?? 'No SKU'} • '
                              'Stock ${product['stock'] ?? 0}',
                            ),
                            trailing:
                                PopupMenuButton<String>(
                              onSelected: (value) async {
                                if (value == 'edit') {
                                  await form(product);
                                }

                                if (value == 'stock') {
                                  await adjustStock(product);
                                }

                                if (value == 'delete') {
                                  await deleteProduct(product);
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Edit'),
                                ),
                                PopupMenuItem(
                                  value: 'stock',
                                  child: Text(
                                    'Adjust stock',
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Delete'),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

/// Opens a WhatsApp chat with the sale's customer (their sale phone number),
/// pre-filled with the "your goods have arrived" message. The message is
/// built on the server from the sale and the bank details in Settings, so
/// an account change never needs an app update.
Future<void> openArrivalNotice(
  BuildContext context,
  ApiClient api,
  int saleId,
) async {
  void say(String text) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text)),
      );
    }
  }

  try {
    final notice = await api.arrivalNotice(saleId);
    final url = '${notice['whatsapp_url'] ?? ''}';

    if (url.isEmpty) {
      throw Exception('No WhatsApp link was returned.');
    }

    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );

    if (!opened) {
      say('Could not open WhatsApp on this device.');
    }
  } catch (e) {
    say('$e');
  }
}

class WebSalesPage extends StatefulWidget {
  const WebSalesPage({super.key, required this.api, required this.repo});

  final ApiClient api;
  final SyncRepository repo;

  @override
  State<WebSalesPage> createState() => _WebSalesPageState();
}

class _WebSalesPageState extends State<WebSalesPage> {
  List<dynamic> rows = [];
  bool busy = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      rows = await widget.api.sales();
    } catch (_) {}

    if (mounted) {
      setState(() => busy = false);
    }
  }

  Future<void> changeStatus(int id, String current) async {
    String selected = const ['New', 'Packed', 'Shipped', 'Delivered', 'Cancelled'].contains(current)
        ? current
        : 'New';

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Update status'),
              content: DropdownButtonFormField<String>(
                value: selected,
                items: const [
                  'New',
                  'Packed',
                  'Shipped',
                  'Delivered',
                  'Cancelled',
                ]
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(value),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(
                      () => selected = value,
                    );
                  }
                },
              ),
              actions: [
                TextButton(
                  onPressed: () =>
                      Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.pop(dialogContext, true),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok != true) return;

    try {
      await widget.api.updateSaleStatus(
        id,
        {'status': selected},
      );

      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userFacingError(e))),
        );
      }
    }
  }

  Future<void> changePaymentStatus(int id, String current) async {
    String selected =
        ['Paid', 'Pending', 'Refunded'].contains(current) ? current : 'Pending';

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Update payment status'),
              content: DropdownButtonFormField<String>(
                value: selected,
                items: const [
                  'Paid',
                  'Pending',
                  'Refunded',
                ]
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(value),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(
                      () => selected = value,
                    );
                  }
                },
              ),
              actions: [
                TextButton(
                  onPressed: () =>
                      Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.pop(dialogContext, true),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok != true) return;

    try {
      await widget.api.updateSaleStatus(
        id,
        {'payment_status': selected},
      );

      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userFacingError(e))),
        );
      }
    }
  }

  Future<void> settleShipping(int id) async {
    if (!await BiometricGuard.require(
      context,
      reason: 'Verify your identity before settling shipping for this sale.',
    )) return;

    try {
      await widget.api.settleShipping(id, {});
      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userFacingError(e))),
        );
      }
    }
  }

  // Share and print both go through one popup so each is a fresh tap
  // (see invoice_actions.dart for why that matters).
  Future<void> shareInvoice(int id) =>
      showInvoiceDialog(context, widget.api, id);

  Future<void> printInvoice(int id) =>
      showInvoiceDialog(context, widget.api, id);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales'),
        actions: [
          IconButton(
            tooltip: 'New stock sale',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => NewSalePage(
                  repo: widget.repo,
                  stocked: true,
                ),
              ),
            ).then((_) => load()),
            icon: const Icon(Icons.inventory_2_outlined),
          ),
          IconButton(
            tooltip: 'New preorder sale',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => NewSalePage(repo: widget.repo),
              ),
            ).then((_) => load()),
            icon: const Icon(Icons.add_shopping_cart),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: load,
        child: busy
            ? ListView(
                children: const [
                  SizedBox(height: 160),
                  Center(child: BrandLoader()),
                ],
              )
            : rows.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 160),
                  Center(
                    child: Text('No sales found.'),
                  ),
                ],
              )
            : ListView.builder(
                itemCount: rows.length,
                itemBuilder: (_, index) {
                  final sale =
                      Map<String, dynamic>.from(
                    rows[index] as Map,
                  );

                  return Card(
                    child: ListTile(
                      title: Text(
                        '${sale['order_id'] ?? '#${sale['id']}'}'
                        ' • ${sale['customer_name'] ?? ''}',
                      ),
                      subtitle: Text(
                        '${sale['journey_label'] ?? sale['order_status'] ?? ''}'
                        ' • ${sale['payment_status'] ?? ''}'
                        ' • ₦${sale['total_amount'] ?? 0}',
                      ),
                      trailing:
                          PopupMenuButton<String>(
                        onSelected: (value) async {
                          if (value == 'status') {
                            await changeStatus(
                              sale['id'] as int,
                              '${sale['order_status'] ?? ''}',
                            );
                          }

                          if (value == 'payment_status') {
                            await changePaymentStatus(
                              sale['id'] as int,
                              '${sale['payment_status'] ?? ''}',
                            );
                          }

                          if (value == 'settle') {
                            await settleShipping(
                              sale['id'] as int,
                            );
                          }

                          if (value == 'notify') {
                            await openArrivalNotice(
                              context,
                              widget.api,
                              sale['id'] as int,
                            );
                          }

                          if (value == 'share_invoice') {
                            await shareInvoice(
                              sale['id'] as int,
                            );
                          }

                          if (value == 'print_invoice') {
                            await printInvoice(
                              sale['id'] as int,
                            );
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'status',
                            child: Text(
                              'Update status',
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'payment_status',
                            child: Text(
                              'Update payment status',
                            ),
                          ),
                          if (sale['batch_id'] != null &&
                              sale['shipping_payment_settled'] !=
                                  true)
                            const PopupMenuItem(
                              value: 'settle',
                              child: Text(
                                'Settle shipping',
                              ),
                            ),
                          // actual_shipping_cost is only filled in once the batch
                          // has arrived — that's when customers get notified.
                          if (sale['batch_id'] != null &&
                              sale['actual_shipping_cost'] != null &&
                              sale['shipping_payment_settled'] != true)
                            const PopupMenuItem(
                              value: 'notify',
                              child: Text(
                                'Notify customer on WhatsApp',
                              ),
                            ),
                          const PopupMenuDivider(),
                          const PopupMenuItem(
                            value: 'share_invoice',
                            child: Text('Share invoice / receipt'),
                          ),
                          const PopupMenuItem(
                            value: 'print_invoice',
                            child: Text('Print invoice / receipt'),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class BatchesPage extends StatefulWidget {
  const BatchesPage({super.key, required this.api, this.isAdmin = false});

  final ApiClient api;
  final bool isAdmin;

  @override
  State<BatchesPage> createState() => _BatchesPageState();
}

class _BatchesPageState extends State<BatchesPage> {
  List<dynamic> rows = [];
  bool busy = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      rows = await widget.api.batches();
    } catch (_) {}

    if (mounted) {
      setState(() => busy = false);
    }
  }

  Future<void> create() async {
    final name = TextEditingController();
    final notes = TextEditingController();
    // How the batch travels decides how its sales are priced:
    // sea by CBM, air by volumetric kg.
    String mode = 'sea';

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('New shipment batch'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Travels by'),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'sea',
                        label: Text('Sea'),
                        icon: Icon(Icons.directions_boat),
                      ),
                      ButtonSegment(
                        value: 'air',
                        label: Text('Air'),
                        icon: Icon(Icons.flight),
                      ),
                    ],
                    selected: {mode},
                    onSelectionChanged: (value) {
                      setDialogState(() => mode = value.first);
                    },
                  ),
                  const SizedBox(height: 6),
                  Text(
                    mode == 'air'
                        ? 'Priced by volumetric kg × the monthly Air rate, '
                            'plus weight × the packing rate.'
                        : 'Priced by CBM × the monthly Sea rate, '
                            'plus weight × the packing rate.',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: notes,
                    decoration: const InputDecoration(
                      labelText: 'Notes',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(dialogContext, true),
                child: const Text('Create'),
              ),
            ],
          ),
        );
      },
    );

    if (ok != true) return;

    try {
      await widget.api.createBatch({
        'name': name.text.trim(),
        'transport_mode': mode,
        'notes': notes.text.trim(),
      });

      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userFacingError(e))),
        );
      }
    }
  }

  Future<void> manageBatch(
    Map<String, dynamic> batch,
  ) async {
    final allSales = await widget.api.sales();
    if (!mounted) return;

    final saleIds = List<int>.from(
      (batch['sale_ids'] as List? ?? const [])
          .map((x) => x is int ? x : int.parse('${x}')),
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final assigned = allSales.where((sale) {
          return sale['id'] != null &&
              saleIds.contains(sale['id'] as int);
        }).toList();

        final available = allSales.where((sale) {
          return sale['id'] != null &&
              sale['batch_id'] == null &&
              sale['order_status'] != 'Cancelled' &&
              !isStockSale(sale);
        }).take(100).toList();

        final selectedRemove = <int>{};
        final selectedAdd = <int>{};

        return StatefulBuilder(
          builder: (context, setSheetState) {
            final inTransit = batch['status'] == 'In Transit';

            Future<void> submitBulk({
              required bool add,
            }) async {
              final ids = add ? selectedAdd : selectedRemove;
              if (ids.isEmpty) {
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  SnackBar(
                    content: Text(
                      add
                          ? 'Select at least one sale to add.'
                          : 'Select at least one sale to remove.',
                    ),
                  ),
                );
                return;
              }

              try {
                await widget.api.updateBatchSalesBulk(
                  batch['id'] as int,
                  addSaleIds: add ? ids.toList() : const [],
                  removeSaleIds: add ? const [] : ids.toList(),
                );
                if (sheetContext.mounted) {
                  Navigator.pop(sheetContext);
                }
                await load();
              } catch (e) {
                if (sheetContext.mounted) {
                  ScaffoldMessenger.of(sheetContext).showSnackBar(
                    SnackBar(content: Text(userFacingError(e))),
                  );
                }
              }
            }

            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(context).size.height * .88,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${batch['name'] ?? 'Batch'} • ${batch['status'] ?? ''}',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(sheetContext),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          Text(
                            'Sales in this batch (${assigned.length})',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          if (!inTransit)
                            const Padding(
                              padding: EdgeInsets.only(top: 5),
                              child: Text(
                                'This batch has arrived, so its sales can no longer be changed here.',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ),
                          if (inTransit && assigned.isNotEmpty)
                            ...assigned.map(
                              (sale) => CheckboxListTile(
                                value: selectedRemove.contains(sale['id']),
                                onChanged: (checked) {
                                  setSheetState(() {
                                    if (checked == true) {
                                      selectedRemove.add(sale['id'] as int);
                                    } else {
                                      selectedRemove.remove(sale['id']);
                                    }
                                  });
                                },
                                title: Text(
                                  '${sale['order_id'] ?? sale['id']} • '
                                  '${sale['customer_name'] ?? ''}',
                                ),
                                subtitle: const Text(
                                  'Select to remove from this batch',
                                ),
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          if (inTransit && assigned.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Text('No sales assigned.'),
                            ),
                          if (inTransit && selectedRemove.isNotEmpty)
                            FilledButton.tonalIcon(
                              onPressed: () => submitBulk(add: false),
                              icon: const Icon(Icons.remove_circle_outline),
                              label: Text(
                                'Remove ${selectedRemove.length} selected',
                              ),
                            ),
                          if (inTransit) ...[
                            const Divider(height: 28),
                            Text(
                              'Available sales (${available.length})',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Select more than one sale, then add them all at once.',
                              style: TextStyle(color: Colors.grey),
                            ),
                            const SizedBox(height: 8),
                            ...available.map(
                              (sale) => CheckboxListTile(
                                value: selectedAdd.contains(sale['id']),
                                onChanged: (checked) {
                                  setSheetState(() {
                                    if (checked == true) {
                                      selectedAdd.add(sale['id'] as int);
                                    } else {
                                      selectedAdd.remove(sale['id']);
                                    }
                                  });
                                },
                                title: Text(
                                  '${sale['order_id'] ?? sale['id']} • '
                                  '${sale['customer_name'] ?? ''}',
                                ),
                                subtitle: Text(
                                  '${sale['customer_state'] ?? 'No state'} • '
                                  '${sale['sale_date'] ?? ''}',
                                ),
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                            if (selectedAdd.isNotEmpty)
                              FilledButton.icon(
                                onPressed: () => submitBulk(add: true),
                                icon: const Icon(Icons.add_circle_outline),
                                label: Text(
                                  'Add ${selectedAdd.length} selected',
                                ),
                              ),
                          ],
                          if (!inTransit) ...[
                            const SizedBox(height: 16),
                            ...assigned.map(
                              (sale) {
                                final settled =
                                    sale['shipping_payment_settled'] == true;
                                final cost = sale['actual_shipping_cost'];
                                return ListTile(
                                  title: Text(
                                    '${sale['order_id'] ?? sale['id']} • '
                                    '${sale['customer_name'] ?? ''}',
                                  ),
                                  subtitle: cost == null
                                      ? null
                                      : Text(
                                          settled
                                              ? 'Shipping ₦${(cost as num).toStringAsFixed(2)} — settled, ready for delivery'
                                              : 'Shipping ₦${(cost as num).toStringAsFixed(2)}',
                                        ),
                                  trailing: settled
                                      ? const Icon(
                                          Icons.check_circle,
                                          color: Colors.green,
                                        )
                                      : null,
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> arriveBatch(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Mark batch as arrived?'),
        content: const Text(
          'This calculates the actual shipping cost for every sale in '
          'this batch using this month\'s rate for the way it travelled '
          '(Sea: CBM × the Sea rate. Air: volumetric kg × the Air rate), '
          'plus each sale\'s weight × the packing rate. '
          'An admin can undo an accidental arrival before any sale is settled.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm arrival'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    if (!await BiometricGuard.require(
      context,
      reason: 'Verify your identity before marking this shipment batch as arrived.',
    )) return;

    try {
      await widget.api.arriveBatch(id, {});
      await load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Batch marked arrived — shipping costs calculated.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userFacingError(e))),
        );
      }
    }
  }

  Future<void> undoArrival(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Undo batch arrival?'),
        content: const Text(
          'This returns every sale in the batch to its travel milestone '
          '(On sea or On air), clears the arrival shipping calculation and '
          'puts the batch back In Transit. It is only allowed before any '
          'sale in the batch has settled shipping or entered a delivery.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Undo arrival'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    if (!await BiometricGuard.require(
      context,
      reason: 'Verify your identity before undoing a shipment arrival.',
    )) return;

    try {
      await widget.api.undoBatchArrival(id);
      await load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Batch returned to In Transit.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userFacingError(e))),
        );
      }
    }
  }

  Future<void> deleteBatch(int id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete shipment batch?'),
        content: Text(
          'Delete "$name"? Sales will not be deleted; they will be detached from this batch.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    if (!await BiometricGuard.require(
      context,
      reason: 'Verify your identity before deleting this shipment batch.',
    )) return;

    try {
      await widget.api.deleteBatch(id);
      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userFacingError(e))),
        );
      }
    }
  }

  Future<void> notifyCustomer(
    BuildContext sheetContext,
    int saleId,
  ) =>
      openArrivalNotice(sheetContext, widget.api, saleId);

  Future<void> settleFromBatch(
    BuildContext sheetContext,
    int saleId,
  ) async {
    if (!await BiometricGuard.require(
      sheetContext,
      reason: 'Verify your identity before settling this shipping payment.',
    )) return;

    try {
      await widget.api.settleShipping(saleId, {});
      if (sheetContext.mounted) {
        Navigator.pop(sheetContext);
      }
      await load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Shipping settled — sale is now ready for delivery.',
            ),
          ),
        );
      }
    } catch (e) {
      if (sheetContext.mounted) {
        ScaffoldMessenger.of(sheetContext).showSnackBar(
          SnackBar(content: Text(userFacingError(e))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shipment batches'),
        actions: [
          IconButton(
            onPressed: create,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: load,
        child: busy
            ? ListView(
                children: const [
                  SizedBox(height: 160),
                  Center(child: BrandLoader()),
                ],
              )
            : rows.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 160),
                  Center(
                    child: Text('No shipment batches.'),
                  ),
                ],
              )
            : ListView.builder(
                itemCount: rows.length,
                itemBuilder: (_, index) {
                  final batch =
                      Map<String, dynamic>.from(
                    rows[index] as Map,
                  );

                  final saleCount =
                      (batch['sale_ids'] as List?)
                              ?.length ??
                          0;

                  return Card(
                    child: ListTile(
                      leading: Icon(
                        batch['transport_mode'] == 'air'
                            ? Icons.flight
                            : Icons.directions_boat,
                        color: batch['transport_mode'] == 'air'
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.secondary,
                      ),
                      title: Text(
                        '${batch['name'] ?? ''}',
                      ),
                      subtitle: Text(
                        '${batch['transport_mode'] == 'air' ? 'Air' : 'Sea'}'
                        ' • ${batch['status'] ?? ''}'
                        ' • $saleCount sales',
                      ),
                      onTap: () => manageBatch(batch),
                      trailing: widget.isAdmin
                          ? PopupMenuButton<String>(
                              onSelected: (value) async {
                                if (value == 'arrive') {
                                  await arriveBatch(batch['id'] as int);
                                } else if (value == 'undo') {
                                  await undoArrival(batch['id'] as int);
                                } else if (value == 'delete') {
                                  await deleteBatch(
                                    batch['id'] as int,
                                    '${batch['name'] ?? 'Batch'}',
                                  );
                                }
                              },
                              itemBuilder: (_) => [
                                if (batch['status'] == 'In Transit')
                                  const PopupMenuItem(
                                    value: 'arrive',
                                    child: Text('Mark arrived'),
                                  ),
                                if (batch['status'] == 'Arrived - Awaiting Shipping Payment')
                                  const PopupMenuItem(
                                    value: 'undo',
                                    child: Text('Undo arrival'),
                                  ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Delete batch'),
                                ),
                              ],
                            )
                          : null,
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class DeliveriesPage extends StatefulWidget {
  const DeliveriesPage({super.key, required this.api});

  final ApiClient api;

  @override
  State<DeliveriesPage> createState() =>
      _DeliveriesPageState();
}

class _DeliveriesPageState
    extends State<DeliveriesPage> {
  List<dynamic> rows = [];
  List<dynamic> readySales = [];
  // Groups of ready sales that could share one courier bag (same phone,
  // name, city or state). Suggestions only.
  List<dynamic> groups = [];
  String? loadError;
  bool busy = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final results = await Future.wait([
        widget.api.deliveries(),
        widget.api.readyDeliveries(),
      ]);

      rows = List<dynamic>.from(results[0]);
      readySales = List<dynamic>.from(results[1]);
      loadError = null;
    } catch (e) {
      loadError = '$e';
    }

    // Suggestions are a bonus: if this fails (e.g. an older server), the
    // page still works exactly as before.
    try {
      groups = await widget.api.deliverySuggestions();
    } catch (_) {
      groups = [];
    }

    if (mounted) {
      setState(() => busy = false);
    }
  }

  Future<void> create() async {
    if (readySales.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No sales are ready for delivery.',
            ),
          ),
        );
      }
      return;
    }

    final selected = <int>{};

    final method = TextEditingController(
      text: 'Dispatch Rider',
    );
    final address = TextEditingController();
    final notes = TextEditingController();

    String describe(dynamic sale) {
      final parts = <String>[
        '${sale['customer_name'] ?? ''}',
        if ('${sale['customer_phone'] ?? ''}'.isNotEmpty)
          '${sale['customer_phone']}',
        if ('${sale['customer_city'] ?? ''}'.isNotEmpty)
          '${sale['customer_city']}',
        if ('${sale['customer_state'] ?? ''}'.isNotEmpty)
          '${sale['customer_state']}',
      ];
      return parts.where((x) => x.isNotEmpty).join(' • ');
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Create delivery'),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: method,
                        decoration: const InputDecoration(
                          labelText: 'Method',
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: address,
                        decoration: const InputDecoration(
                          labelText: 'Delivery address',
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: notes,
                        decoration: const InputDecoration(
                          labelText: 'Notes',
                        ),
                      ),
                      if (groups.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Text(
                          'Could share one courier bag (optional)',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          children: groups.map((g) {
                            final ids = List<int>.from(
                              (g['sale_ids'] as List).map(
                                (x) => x is int ? x : int.parse('$x'),
                              ),
                            );
                            final value = '${g['value'] ?? ''}';
                            return ActionChip(
                              avatar: const Icon(
                                Icons.shopping_bag_outlined,
                                size: 18,
                              ),
                              label: Text(
                                '${g['label']}'
                                '${value.isEmpty ? '' : ': $value'}'
                                ' (${ids.length})',
                              ),
                              onPressed: () {
                                setDialogState(() {
                                  selected
                                    ..clear()
                                    ..addAll(ids);
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ],
                      const SizedBox(height: 8),
                      ...readySales.map(
                        (sale) => CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: selected.contains(
                            sale['id'],
                          ),
                          title: Text(
                            '${sale['order_id'] ?? sale['id']}'
                            ' • ${sale['customer_name'] ?? ''}',
                          ),
                          subtitle: Text(describe(sale)),
                          onChanged: (value) {
                            setDialogState(() {
                              final id = sale['id'] as int;

                              if (value == true) {
                                selected.add(id);
                              } else {
                                selected.remove(id);
                              }
                            });
                          },
                        ),
                      ),
                      if (selected.length > 1)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '${selected.length} orders will go in one '
                            'courier bag with one label.',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () =>
                      Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: selected.isEmpty
                      ? null
                      : () => Navigator.pop(
                            dialogContext,
                            true,
                          ),
                  child: Text(
                    selected.length > 1 ? 'Create bag' : 'Create',
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok != true) return;

    try {
      final created = await widget.api.createDelivery({
        'sale_ids': selected.toList(),
        'method': method.text.trim(),
        'delivery_address': address.text.trim(),
        'notes': notes.text.trim(),
      });

      await load();

      // A consolidated bag needs its own label — go straight to it.
      final newId = created['id'];
      if (selected.length > 1 && newId is int && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Courier bag created for ${selected.length} orders. '
              'Add its label details next.',
            ),
          ),
        );
        await labelData(newId);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userFacingError(e))),
        );
      }
    }
  }

  Future<void> labelData(int id) async {
    final weight = TextEditingController();
    final dimensions = TextEditingController();
    final remarks = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Label package data'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: weight,
                keyboardType:
                    const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Weight kg',
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: dimensions,
                decoration: const InputDecoration(
                  labelText: 'Dimensions',
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: remarks,
                decoration: const InputDecoration(
                  labelText: 'Remarks',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (ok != true) return;

    final parsedWeight =
        double.tryParse(weight.text.trim());

    if (parsedWeight == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Enter a valid package weight.',
            ),
          ),
        );
      }
      return;
    }

    try {
      await widget.api.saveLabelData(
        id,
        {
          'package_weight_kg': parsedWeight,
          'package_dimensions':
              dimensions.text.trim(),
          'remarks': remarks.text.trim(),
        },
      );

      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userFacingError(e))),
        );
      }
    }
  }

  Future<void> sharePdf(int id) async {
    try {
      final Uint8List bytes =
          await widget.api.labelPdf(id);

      await Share.shareXFiles(
        [
          XFile.fromData(
            bytes,
            mimeType: 'application/pdf',
            name: 'label-$id.pdf',
          ),
        ],
        text: 'Delivery label #$id',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userFacingError(e))),
        );
      }
    }
  }

  Future<void> printPdf(int id) async {
    try {
      final Uint8List bytes =
          await widget.api.labelPdf(id);

      // Printing.layoutPdf opens the platform's native print dialog (and a
      // PDF preview first, on most platforms) — works the same way on
      // Android, iOS, desktop and web, with no per-platform code needed here.
      await Printing.layoutPdf(
        name: 'label-$id.pdf',
        onLayout: (_) async => bytes,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userFacingError(e))),
        );
      }
    }
  }

  Future<void> updateStatus(
    int id,
    String status,
  ) async {
    try {
      await widget.api.updateDeliveryStatus(
        id,
        {'status': status},
      );

      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userFacingError(e))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Deliveries'),
        actions: [
          IconButton(
            onPressed: create,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: load,
        child: busy
            ? ListView(
                children: const [
                  SizedBox(height: 160),
                  Center(child: BrandLoader()),
                ],
              )
            : ListView(
          children: [
            if (loadError != null)
              Card(
                margin: const EdgeInsets.all(12),
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  leading: const Icon(Icons.error_outline),
                  title: const Text('Could not load deliveries'),
                  subtitle: Text(loadError!),
                  trailing: IconButton(
                    onPressed: load,
                    icon: const Icon(Icons.refresh),
                  ),
                ),
              ),
            if (readySales.isNotEmpty)
              Card(
                margin: const EdgeInsets.all(12),
                color: Theme.of(context)
                    .colorScheme
                    .secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment
                            .spaceBetween,
                        children: [
                          Text(
                            'Ready for delivery (${readySales.length})',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          FilledButton.icon(
                            onPressed: create,
                            icon: const Icon(
                              Icons.local_shipping,
                            ),
                            label: const Text(
                              'Create delivery',
                            ),
                          ),
                        ],
                      ),
                      if (groups.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '${groups.length} group(s) of orders could share '
                            'a courier bag — tap Create delivery to see them.',
                          ),
                        ),
                      const SizedBox(height: 8),
                      ...readySales.map(
                        (sale) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '${sale['order_id'] ?? sale['id']}'
                            ' • ${sale['customer_name'] ?? ''}',
                          ),
                          subtitle: sale[
                                      'actual_shipping_cost'] !=
                                  null
                              ? Text(
                                  'Shipping settled: ₦${(sale['actual_shipping_cost'] as num).toStringAsFixed(2)}',
                                )
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 4,
              ),
              child: Text(
                'Deliveries',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            if (rows.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Text('No deliveries found.'),
                ),
              )
            else
              ...rows.map((row) {
                final delivery =
                    Map<String, dynamic>.from(row as Map);

                  final count =
                      (delivery['sale_ids'] as List?)
                              ?.length ??
                          0;

                  return Card(
                    child: ListTile(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DeliveryDetailPage(
                            api: widget.api,
                            delivery: delivery,
                          ),
                        ),
                      ).then((_) => load()),
                      title: Text(
                        'Delivery #${delivery['id']}'
                        ' • ${delivery['method'] ?? ''}',
                      ),
                      subtitle: Text(
                        '${delivery['status'] ?? ''}'
                        ' • $count sale(s)'
                        '${delivery['is_consolidated'] == true ? ' • Courier bag' : ''}'
                        '${delivery['is_consolidated'] == true && delivery['consolidation_type'] != null ? ' (same ${delivery['consolidation_type']})' : ''}',
                      ),
                      leading: delivery['is_consolidated'] == true
                          ? const Icon(Icons.shopping_bag)
                          : const Icon(Icons.local_shipping_outlined),
                      trailing:
                          PopupMenuButton<String>(
                        onSelected: (value) async {
                          final id =
                              delivery['id'] as int;

                          if (value == 'label') {
                            await labelData(id);
                            return;
                          }

                          if (value == 'pdf') {
                            await sharePdf(id);
                            return;
                          }

                          if (value == 'print') {
                            await printPdf(id);
                            return;
                          }

                          await updateStatus(
                            id,
                            value,
                          );
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'Pending',
                            child: Text('Pending'),
                          ),
                          PopupMenuItem(
                            value: 'Out for Delivery',
                            child: Text(
                              'Out for Delivery',
                            ),
                          ),
                          PopupMenuItem(
                            value: 'Delivered',
                            child: Text('Delivered'),
                          ),
                          PopupMenuDivider(),
                          PopupMenuItem(
                            value: 'label',
                            child: Text(
                              'Enter label data',
                            ),
                          ),
                          PopupMenuItem(
                            value: 'print',
                            child: Text(
                              'Print label',
                            ),
                          ),
                          PopupMenuItem(
                            value: 'pdf',
                            child: Text(
                              'Download / share label PDF',
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          ),
      ),
    );
  }
}

class DeliveryDetailPage extends StatefulWidget {
  const DeliveryDetailPage({
    super.key,
    required this.api,
    required this.delivery,
  });

  final ApiClient api;
  final Map<String, dynamic> delivery;

  @override
  State<DeliveryDetailPage> createState() =>
      _DeliveryDetailPageState();
}

class _DeliveryDetailPageState
    extends State<DeliveryDetailPage> {
  late Map<String, dynamic> delivery;
  List<Map<String, dynamic>> sales = [];
  bool loading = true;
  String? error;

  int get id => delivery['id'] as int;

  @override
  void initState() {
    super.initState();
    delivery = Map<String, dynamic>.from(widget.delivery);
    load();
  }

  Future<void> load() async {
    try {
      final results = await Future.wait([
        widget.api.deliveries(),
        widget.api.sales(),
      ]);

      final fresh = results[0]
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .where((d) => d['id'] == id);
      if (fresh.isNotEmpty) delivery = fresh.first;

      final ids = ((delivery['sale_ids'] as List?) ?? []).toSet();
      sales = results[1]
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .where((s) => ids.contains(s['id']))
          .toList();
      error = null;
    } catch (e) {
      error = '$e';
    }

    if (mounted) setState(() => loading = false);
  }

  void _snack(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(userFacingError(e))),
    );
  }

  Future<void> setStatus(String status) async {
    try {
      await widget.api.updateDeliveryStatus(
        id,
        {'status': status},
      );
      await load();
    } catch (e) {
      _snack(e);
    }
  }

  bool get _hasPackageDetails =>
      delivery['package_weight_kg'] != null &&
      '${delivery['package_dimensions'] ?? ''}'.trim().isNotEmpty;

  /// Weight + dimensions are required before a label can be generated
  /// (same rule as the website). Returns true once they are saved.
  Future<bool> enterPackageDetails() async {
    final weight = TextEditingController(
      text: delivery['package_weight_kg'] == null
          ? ''
          : '${delivery['package_weight_kg']}',
    );
    final dimensions = TextEditingController(
      text: '${delivery['package_dimensions'] ?? ''}',
    );
    final remarks = TextEditingController(
      text: '${delivery['remarks'] ?? ''}',
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Package weight & dimensions'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: weight,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Weight (kg)',
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: dimensions,
                decoration: const InputDecoration(
                  labelText: 'Dimensions',
                  hintText: 'e.g. 30 x 20 x 15 cm',
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: remarks,
                decoration: const InputDecoration(
                  labelText: 'Remarks (optional)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (ok != true) return false;

    final parsedWeight = double.tryParse(weight.text.trim());
    if (parsedWeight == null || parsedWeight <= 0) {
      _snack('Enter a valid package weight (greater than 0).');
      return false;
    }
    if (dimensions.text.trim().isEmpty) {
      _snack('Enter the package dimensions.');
      return false;
    }

    try {
      await widget.api.saveLabelData(id, {
        'package_weight_kg': parsedWeight,
        'package_dimensions': dimensions.text.trim(),
        'remarks': remarks.text.trim(),
      });
      await load();
      return true;
    } catch (e) {
      _snack(e);
      return false;
    }
  }

  Future<void> printLabel() async {
    if (!_hasPackageDetails && !await enterPackageDetails()) return;
    try {
      final Uint8List bytes = await widget.api.labelPdf(id);
      await Printing.layoutPdf(
        name: 'label-$id.pdf',
        onLayout: (_) async => bytes,
      );
    } catch (e) {
      _snack(e);
    }
  }

  Future<void> shareLabel() async {
    if (!_hasPackageDetails && !await enterPackageDetails()) return;
    try {
      final Uint8List bytes = await widget.api.labelPdf(id);
      await Share.shareXFiles(
        [
          XFile.fromData(
            bytes,
            mimeType: 'application/pdf',
            name: 'label-$id.pdf',
          ),
        ],
        text: 'Delivery label #$id',
      );
    } catch (e) {
      _snack(e);
    }
  }

  String _dt(dynamic v) => v == null
      ? '—'
      : '$v'.replaceFirst('T', ' ').split('.').first;

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
              child: Text(
                k,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(child: Text(v.isEmpty ? '—' : v)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final status = '${delivery['status'] ?? ''}';

    return Scaffold(
      appBar: AppBar(title: Text('Delivery #$id')),
      body: loading
          ? const Center(child: BrandLoader())
          : RefreshIndicator(
              onRefresh: load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (error != null)
                    Padding(
                      padding:
                          const EdgeInsets.only(bottom: 12),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .error,
                        ),
                      ),
                    ),
                  Wrap(
                    spacing: 8,
                    children: [
                      Chip(label: Text(status)),
                      if (delivery['is_consolidated'] == true)
                        Chip(
                          label: Text(
                            'Consolidated'
                            ' (${delivery['consolidation_type'] ?? ''})',
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _kv('Method', '${delivery['method'] ?? ''}'),
                  _kv(
                    'Delivery address',
                    '${delivery['delivery_address'] ?? ''}',
                  ),
                  _kv('Created', _dt(delivery['created_at'])),
                  _kv('Shipped', _dt(delivery['shipped_at'])),
                  _kv(
                    'Delivered at',
                    _dt(delivery['delivered_at']),
                  ),
                  _kv('Notes', '${delivery['notes'] ?? ''}'),
                  if (delivery['package_weight_kg'] != null)
                    _kv(
                      'Package weight',
                      '${delivery['package_weight_kg']} kg',
                    ),
                  if (delivery['package_dimensions'] != null)
                    _kv(
                      'Dimensions',
                      '${delivery['package_dimensions']}',
                    ),
                  if (delivery['remarks'] != null)
                    _kv('Remarks', '${delivery['remarks']}'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: status == 'Pending'
                            ? () => setStatus('Out for Delivery')
                            : null,
                        child:
                            const Text('Mark out for delivery'),
                      ),
                      FilledButton(
                        onPressed: status == 'Delivered'
                            ? null
                            : () => setStatus('Delivered'),
                        child: const Text('Mark delivered'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: enterPackageDetails,
                        icon: const Icon(Icons.scale),
                        label: Text(
                          _hasPackageDetails
                              ? 'Edit weight & dimensions'
                              : 'Enter weight & dimensions',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: printLabel,
                        icon: const Icon(Icons.print),
                        label: const Text('Print label'),
                      ),
                      OutlinedButton.icon(
                        onPressed: shareLabel,
                        icon: const Icon(Icons.download),
                        label: const Text('Download / share'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Sales in this parcel (${sales.length})',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (sales.isEmpty)
                    const Text('No sales found for this delivery.'),
                  ...sales.map((sale) {
                    final items =
                        (sale['items'] as List?) ?? const [];
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${sale['order_id'] ?? sale['id']}'
                              ' • ${sale['customer_name'] ?? ''}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '${sale['customer_phone'] ?? ''}'
                              ' • ${sale['customer_state'] ?? ''}',
                            ),
                            const Divider(),
                            ...items.whereType<Map>().map(
                                  (item) => Padding(
                                    padding:
                                        const EdgeInsets.symmetric(
                                      vertical: 2,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '${item['product_name'] ?? item['product_id']}'
                                            '${(item['variant_note'] ?? '').toString().isEmpty ? '' : ' (${item['variant_note']})'}',
                                          ),
                                        ),
                                        Text('× ${item['qty']}'),
                                      ],
                                    ),
                                  ),
                                ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }
}

class RatesPage extends StatelessWidget {
  const RatesPage({super.key, required this.api, this.isAdmin = false});

  final ApiClient api;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Shipping rates'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Courier'),
              Tab(text: 'Monthly'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _RateList(
              api: api,
              courier: true,
              isAdmin: isAdmin,
            ),
            _MonthlyRates(api: api, isAdmin: isAdmin),
          ],
        ),
      ),
    );
  }
}

/// Monthly rates: Sea (NGN per CBM) and Air (NGN per volumetric kg) are
/// both set here, one list each.
class _MonthlyRates extends StatefulWidget {
  const _MonthlyRates({required this.api, this.isAdmin = false});

  final ApiClient api;
  final bool isAdmin;

  @override
  State<_MonthlyRates> createState() => _MonthlyRatesState();
}

class _MonthlyRatesState extends State<_MonthlyRates> {
  bool air = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                label: Text('Sea'),
                icon: Icon(Icons.directions_boat),
              ),
              ButtonSegment(
                value: true,
                label: Text('Air'),
                icon: Icon(Icons.flight),
              ),
            ],
            selected: {air},
            onSelectionChanged: (value) => setState(() => air = value.first),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            air
                ? 'Air: ₦ per volumetric kg, used for batches that travel by air.'
                : 'Sea: ₦ per CBM, used for batches that travel by sea.',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ),
        Expanded(
          child: _RateList(
            key: ValueKey(air),
            api: widget.api,
            courier: false,
            air: air,
            isAdmin: widget.isAdmin,
          ),
        ),
      ],
    );
  }
}

class _RateList extends StatefulWidget {
  const _RateList({
    super.key,
    required this.api,
    required this.courier,
    this.air = false,
    this.isAdmin = false,
  });

  final ApiClient api;
  final bool courier;

  /// Monthly AIR rates (₦ per volumetric kg). false = courier or monthly SEA (₦ per CBM).
  final bool air;
  final bool isAdmin;

  @override
  State<_RateList> createState() =>
      _RateListState();
}

class _RateListState extends State<_RateList> {
  List<dynamic> rows = [];
  bool busy = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      rows = widget.courier
          ? await widget.api.courierRates()
          : widget.air
              ? await widget.api.airRates()
              : await widget.api.monthlyRates();
    } catch (_) {}

    if (mounted) {
      setState(() => busy = false);
    }
  }

  Future<void> add() async {
    final first = TextEditingController();
    final rate = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            widget.courier
                ? 'Courier rate'
                : widget.air
                    ? 'Monthly Air rate'
                    : 'Monthly Sea rate',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: first,
                decoration: InputDecoration(
                  labelText: widget.courier
                      ? 'State'
                      : 'Month (YYYY-MM-DD)',
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: rate,
                keyboardType:
                    const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration:
                    InputDecoration(
                  labelText: widget.air
                      ? 'Rate per volumetric kg'
                      : 'Rate per CBM',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (ok != true) return;

    final parsedRate =
        double.tryParse(rate.text.trim());

    if (parsedRate == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Enter a valid rate.',
            ),
          ),
        );
      }
      return;
    }

    if (!await BiometricGuard.require(
      context,
      reason: 'Verify your identity before changing shipping rates.',
    )) return;

    try {
      if (widget.courier) {
        await widget.api.createCourierRate({
          'state': first.text.trim(),
          'rate_per_cbm': parsedRate,
        });
      } else if (widget.air) {
        await widget.api.createAirRate({
          'month': first.text.trim(),
          'rate_per_kg': parsedRate,
        });
      } else {
        await widget.api.createMonthlyRate({
          'month': first.text.trim(),
          'rate_per_cbm': parsedRate,
        });
      }

      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userFacingError(e))),
        );
      }
    }
  }

  Future<void> editRate(
    Map<String, dynamic> row,
  ) async {
    final first = TextEditingController(
      text: widget.courier
          ? '${row['state'] ?? ''}'
          : '${row['month'] ?? ''}',
    );

    final rate = TextEditingController(
      text: widget.air
          ? '${row['rate_per_kg'] ?? ''}'
          : '${row['rate_per_cbm'] ?? ''}',
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Edit rate'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: first,
                decoration:
                    const InputDecoration(
                  labelText: 'State or month',
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: rate,
                keyboardType:
                    const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration:
                    InputDecoration(
                  labelText: widget.air
                      ? 'Rate per volumetric kg'
                      : 'Rate per CBM',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (ok != true) return;

    final parsedRate =
        double.tryParse(rate.text.trim());

    if (parsedRate == null) return;

    if (!await BiometricGuard.require(
      context,
      reason: 'Verify your identity before changing shipping rates.',
    )) return;

    try {
      final id = row['id'] as int;

      if (widget.courier) {
        await widget.api.updateCourierRate(
          id,
          {
            'state': first.text.trim(),
            'rate_per_cbm': parsedRate,
          },
        );
      } else if (widget.air) {
        await widget.api.updateAirRate(
          id,
          {
            'month': first.text.trim(),
            'rate_per_kg': parsedRate,
          },
        );
      } else {
        await widget.api.updateMonthlyRate(
          id,
          {
            'month': first.text.trim(),
            'rate_per_cbm': parsedRate,
          },
        );
      }

      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userFacingError(e))),
        );
      }
    }
  }

  Future<void> deleteRate(
    Map<String, dynamic> row,
  ) async {
    if (!await BiometricGuard.require(
      context,
      reason: 'Verify your identity before deleting this shipping rate.',
    )) return;

    try {
      final id = row['id'] as int;

      if (widget.courier) {
        await widget.api.deleteCourierRate(id);
      } else if (widget.air) {
        await widget.api.deleteAirRate(id);
      } else {
        await widget.api.deleteMonthlyRate(id);
      }

      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userFacingError(e))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: load,
        child: ListView(
          children: [
            ListTile(
              title: Text(
                widget.courier
                    ? 'Courier rates'
                    : widget.air
                        ? 'Monthly Air rates'
                        : 'Monthly Sea rates',
              ),
              subtitle: widget.isAdmin
                  ? null
                  : const Text('Editing this rate is admin-only'),
              trailing: widget.isAdmin
                  ? IconButton(
                      onPressed: add,
                      icon: const Icon(Icons.add),
                    )
                  : const Icon(Icons.lock_outline),
            ),
            if (busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: BrandLoader()),
              )
            else
            ...rows.map(
              (raw) {
                final row =
                    Map<String, dynamic>.from(
                  raw as Map,
                );

                return ListTile(
                  title: Text(
                    widget.courier
                        ? '${row['state'] ?? ''}'
                        : '${row['month'] ?? ''}',
                  ),
                  subtitle: Text(
                    '${(widget.air ? row['rate_per_kg'] : row['rate_per_cbm']) ?? 0}',
                  ),
                  onTap: widget.isAdmin ? () => editRate(row) : null,
                  trailing: widget.isAdmin
                      ? IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                          ),
                          onPressed: () => deleteRate(row),
                        )
                      : null,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key, required this.api});

  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.point_of_sale),
            title: const Text('Sales'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ReportPage(
                  title: 'Sales',
                  type: 'sales',
                  load: api.salesReport,
                  loadRange: api.salesReport,
                ),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.local_shipping),
            title: const Text('Shipping'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ReportPage(
                  title: 'Shipping',
                  type: 'shipping',
                  load: api.shippingReport,
                ),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.inventory_2),
            title: const Text('Inventory'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ReportPage(
                  title: 'Inventory',
                  type: 'inventory',
                  load: api.inventoryReport,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _money(dynamic v) {
  if (v == null) return '₦0.00';
  final n = v is num ? v : num.tryParse('$v') ?? 0;
  return '₦${n.toStringAsFixed(2)}';
}

class ReportPage extends StatefulWidget {
  const ReportPage({
    super.key,
    required this.title,
    required this.type,
    required this.load,
    this.loadRange,
  });

  final String title;
  final String type;
  final Future<dynamic> Function() load;

  /// Only the sales report supports a date range (the API's other reports
  /// are not date-based). When provided, a range picker is shown.
  final Future<dynamic> Function({
    String? startDate,
    String? endDate,
  })? loadRange;

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  DateTimeRange? range;
  late Future<dynamic> future;

  @override
  void initState() {
    super.initState();
    future = _fetch();
  }

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<dynamic> _fetch() {
    final lr = widget.loadRange;
    if (lr != null) {
      return lr(
        startDate: range == null ? null : _iso(range!.start),
        endDate: range == null ? null : _iso(range!.end),
      );
    }
    return widget.load();
  }

  Future<void> pick() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1),
      initialDateRange: range,
    );
    if (picked != null) {
      setState(() {
        range = picked;
        future = _fetch();
      });
    }
  }

  void clear() {
    setState(() {
      range = null;
      future = _fetch();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          if (widget.loadRange != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: pick,
                      icon: const Icon(Icons.date_range),
                      label: Text(
                        range == null
                            ? 'Date range (default: last 30 days)'
                            : '${_iso(range!.start)}  →  ${_iso(range!.end)}',
                      ),
                    ),
                  ),
                  if (range != null)
                    IconButton(
                      onPressed: clear,
                      icon: const Icon(Icons.close),
                      tooltip: 'Back to last 30 days',
                    ),
                ],
              ),
            ),
          Expanded(
            child: FutureBuilder<dynamic>(
              future: future,
              builder: (_, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('${snapshot.error}'),
                    ),
                  );
                }

                if (snapshot.connectionState !=
                        ConnectionState.done &&
                    !snapshot.hasData) {
                  return const Center(
                    child: BrandLoader(),
                  );
                }

                final data = snapshot.data;

                Map<String, dynamic>? totals;
                final List<dynamic> list;

                if (data is Map && data['sales'] is List) {
                  list = List<dynamic>.from(data['sales'] as List);
                  if (data['totals'] is Map) {
                    totals = Map<String, dynamic>.from(
                      data['totals'] as Map,
                    );
                  }
                } else if (data is List) {
                  list = data;
                } else {
                  list = [data];
                }

                final period = (data is Map &&
                        data['start_date'] != null)
                    ? 'Showing ${data['start_date']} to ${data['end_date']}'
                    : null;

                final rows = list
                    .whereType<Map>()
                    .map((m) => Map<String, dynamic>.from(m))
                    .toList();

                return ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    if (period != null)
                      Padding(
                        padding:
                            const EdgeInsets.only(bottom: 8),
                        child: Text(
                          period,
                          style: const TextStyle(
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    if (totals != null)
                      _TotalsCard(totals: totals),
                    if (rows.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(
                          child: Text('No report data.'),
                        ),
                      ),
                    ...rows.map((row) {
                      switch (widget.type) {
                        case 'shipping':
                          return _ShippingRow(row: row);
                        case 'inventory':
                          return _InventoryRow(row: row);
                        default:
                          return _SalesRow(row: row);
                      }
                    }),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.totals});

  final Map<String, dynamic> totals;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Wrap(
          spacing: 20,
          runSpacing: 8,
          children: [
            _totalItem('Subtotal', totals['subtotal']),
            _totalItem(
              'Est. shipping',
              totals['estimated_shipping'],
            ),
            _totalItem(
              'Actual shipping',
              totals['actual_shipping'],
            ),
            _totalItem('Total', totals['total']),
          ],
        ),
      ),
    );
  }

  Widget _totalItem(String label, dynamic value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12),
        ),
        Text(
          _money(value),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ],
    );
  }
}

class _SalesRow extends StatelessWidget {
  const _SalesRow({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(
          '${row['order_id'] ?? row['id'] ?? ''}'
          ' • ${row['customer_name'] ?? ''}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${row['payment_status'] ?? ''} • '
          '${row['order_status'] ?? ''}'
          '${row['sale_date'] != null ? ' • ${'${row['sale_date']}'.split('T').first}' : ''}',
        ),
        trailing: Text(
          _money(row['total_amount']),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

class _ShippingRow extends StatelessWidget {
  const _ShippingRow({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final settled = row['shipping_payment_settled'] == true;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          settled ? Icons.check_circle : Icons.schedule,
          color: settled ? Colors.green : Colors.orange,
        ),
        title: Text(
          '${row['customer_name'] ?? 'Sale #${row['sale_id']}'}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${row['batch_name'] ?? 'No batch'} • '
          '${row['batch_status'] ?? ''}\n'
          'Est: ${_money(row['estimated_shipping_cost'])} • '
          'Actual: ${_money(row['actual_shipping_cost'])}',
        ),
        isThreeLine: true,
        trailing: Text(
          settled ? 'Settled' : 'Pending',
          style: TextStyle(
            color: settled ? Colors.green : Colors.orange,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _InventoryRow extends StatelessWidget {
  const _InventoryRow({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final stock = row['stock'] is int
        ? row['stock'] as int
        : int.tryParse('${row['stock']}') ?? 0;
    final low = stock <= 5;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(
          '${row['name'] ?? ''}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          'SKU: ${row['sku'] ?? '—'} • '
          'Cost: ${_money(row['cost'])} • '
          'CBM: ${row['cbm'] ?? '—'}',
        ),
        trailing: Chip(
          label: Text('Stock: $stock'),
          backgroundColor:
              low ? Colors.red.shade100 : Colors.green.shade100,
          labelStyle: TextStyle(
            color: low
                ? Colors.red.shade900
                : Colors.green.shade900,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.api});

  final ApiClient api;

  @override
  State<SettingsPage> createState() =>
      _SettingsPageState();
}

class _SettingsPageState
    extends State<SettingsPage> {
  final name = TextEditingController();
  final phone = TextEditingController();
  final address = TextEditingController();
  final width = TextEditingController();
  final height = TextEditingController();
  // Shipping payment account, sent to customers when their goods arrive.
  final bankName = TextEditingController();
  final bankNumber = TextEditingController();
  final bankAccountName = TextEditingController();
  // NGN per kg of product weight, added to the CBM charge.
  final kgRate = TextEditingController();

  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final settings =
          await widget.api.settings();

      name.text =
          '${settings['business_name'] ?? ''}';

      phone.text =
          '${settings['business_phone'] ?? ''}';

      address.text =
          '${settings['business_address'] ?? ''}';

      width.text =
          '${settings['label_width_mm'] ?? 100}';

      height.text =
          '${settings['label_height_mm'] ?? 150}';

      bankName.text =
          '${settings['bank_name'] ?? ''}';

      bankNumber.text =
          '${settings['bank_account_number'] ?? ''}';

      bankAccountName.text =
          '${settings['bank_account_name'] ?? ''}';

      final rawKg = settings['shipping_rate_per_kg'];
      kgRate.text = rawKg is num
          ? (rawKg == rawKg.roundToDouble()
              ? rawKg.round().toString()
              : rawKg.toString())
          : '${rawKg ?? ''}';
    } catch (_) {}

    if (mounted) {
      setState(() => loading = false);
    }
  }

  Future<void> save() async {
    final kg = double.tryParse(kgRate.text.trim().replaceAll(',', ''));

    if (kg == null || kg < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter a valid packing rate per kg (0 or more).',
          ),
        ),
      );
      return;
    }

    if (!await BiometricGuard.require(
      context,
      reason: 'Verify your identity before changing business, label, rate or bank settings.',
    )) return;

    try {
      await widget.api.updateSettings({
        'shipping_rate_per_kg': kg,
        'business_name': name.text.trim(),
        'business_phone': phone.text.trim(),
        'business_address': address.text.trim(),
        'label_width_mm':
            int.tryParse(width.text.trim()),
        'label_height_mm':
            int.tryParse(height.text.trim()),
        'bank_name': bankName.text.trim(),
        'bank_account_number': bankNumber.text.trim(),
        'bank_account_name': bankAccountName.text.trim(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Settings saved.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userFacingError(e))),
        );
      }
    }
  }

  Future<void> deleteSelectedSale() async {
    final sales = await widget.api.sales();
    if (!mounted) return;
    int? selected;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Delete selected sale'),
          content: DropdownButtonFormField<int>(
            value: selected,
            decoration: const InputDecoration(labelText: 'Sale'),
            items: sales.whereType<Map>().map((raw) {
              final sale = Map<String, dynamic>.from(raw);
              return DropdownMenuItem<int>(
                value: (sale['id'] as num).toInt(),
                child: Text(
                  '${sale['order_id'] ?? '#${sale['id']}'} • ${sale['customer_name'] ?? 'Customer'}',
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
            onChanged: (value) => setState(() => selected = value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: selected == null
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || selected == null) return;
    if (!await BiometricGuard.require(
      context,
      reason: 'Verify your identity before deleting a sale.',
    )) return;

    try {
      await widget.api.deleteSale(selected!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sale deleted.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(userFacingError(e))));
      }
    }
  }

  Future<void> deleteSelectedBatch() async {
    final batches = await widget.api.batches();
    if (!mounted) return;
    int? selected;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Delete selected shipment batch'),
          content: DropdownButtonFormField<int>(
            value: selected,
            decoration: const InputDecoration(labelText: 'Shipment batch'),
            items: batches.whereType<Map>().map((raw) {
              final batch = Map<String, dynamic>.from(raw);
              return DropdownMenuItem<int>(
                value: (batch['id'] as num).toInt(),
                child: Text(
                  '${batch['name'] ?? 'Batch'} • ${batch['transport_mode'] == 'air' ? 'Air' : 'Sea'} • ${batch['status'] ?? ''}',
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
            onChanged: (value) => setState(() => selected = value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: selected == null
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || selected == null) return;
    if (!await BiometricGuard.require(
      context,
      reason: 'Verify your identity before deleting a shipment batch.',
    )) return;

    try {
      await widget.api.deleteBatch(selected!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Shipment batch deleted.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(userFacingError(e))));
      }
    }
  }

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    address.dispose();
    width.dispose();
    height.dispose();
    bankName.dispose();
    bankNumber.dispose();
    bankAccountName.dispose();
    kgRate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: loading
          ? const Center(
              child: BrandLoader(),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  child: const ListTile(
                    leading: Icon(Icons.fingerprint),
                    title: Text('Biometric verification required'),
                    subtitle: Text(
                      'Saving these settings changes business details, label settings, packing rates or bank details.',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(
                    labelText: 'Business name',
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: phone,
                  decoration: const InputDecoration(
                    labelText: 'Business phone',
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: address,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Business address',
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: width,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Label width (mm)',
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: height,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Label height (mm)',
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Packing rate',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                const Text(
                  'Added to every shipment: weight in kg × this packing rate, '
                  'on top of the volume charge (Sea: CBM × the monthly Sea '
                  'rate, Air: volumetric kg × the monthly Air rate — both set '
                  'on the Rates page). Change it here when the rate changes; '
                  'it applies to new estimates and to batches that arrive '
                  'from now on.',
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: kgRate,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Packing rate per kg (₦)',
                    prefixText: '₦',
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Shipping payment account',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                const Text(
                  'Sent to customers on WhatsApp when their goods arrive, '
                  'together with the business name above. Change it here '
                  'whenever the account changes.',
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: bankName,
                  decoration: const InputDecoration(
                    labelText: 'Bank name',
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: bankNumber,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Account number',
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: bankAccountName,
                  decoration: const InputDecoration(
                    labelText: 'Account name',
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Selected data management',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                const Text(
                  'Use these controls to remove one live sale or one shipment batch without clearing the rest of the database. Sales are protected when shipping has already been settled or a delivery has been created.',
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: deleteSelectedSale,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete selected sale'),
                ),
                OutlinedButton.icon(
                  onPressed: deleteSelectedBatch,
                  icon: const Icon(Icons.delete_sweep_outlined),
                  label: const Text('Delete selected shipment batch'),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: save,
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('Verify & save settings'),
                ),
              ],
            ),
    );
  }
}

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({
    super.key,
    required this.api,
  });

  final ApiClient api;

  @override
  State<ChangePasswordPage> createState() =>
      _ChangePasswordPageState();
}

class _ChangePasswordPageState
    extends State<ChangePasswordPage> {
  final current = TextEditingController();
  final next = TextEditingController();
  final confirm = TextEditingController();
  final newUsername = TextEditingController(text: AppSession.username);

  Future<void> saveUsername() async {
    final u = newUsername.text.trim();
    if (u.isEmpty || u == AppSession.username) return;

    if (!await BiometricGuard.require(
      context,
      reason: 'Verify your identity before changing your username.',
    )) return;

    try {
      final result = await widget.api.changeUsername(u);
      AppSession.username = '${result['username'] ?? u}';

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Username updated.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userFacingError(e))),
        );
      }
    }
  }

  Future<void> save() async {
    if (next.text.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'New password must be at least 8 characters.',
          ),
        ),
      );
      return;
    }

    if (next.text != confirm.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'New passwords do not match.',
          ),
        ),
      );
      return;
    }

    if (!await BiometricGuard.require(
      context,
      reason: 'Verify your identity before changing your password.',
    )) return;

    try {
      final result = await widget.api.changePassword(
        current.text,
        next.text,
      );
      final token = result['token']?.toString();
      if (token != null && token.isNotEmpty) {
        await widget.api.saveToken(token);
      }
      await widget.api.clearBiometricCredential();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Password changed successfully.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userFacingError(e))),
        );
      }
    }
  }

  @override
  void dispose() {
    current.dispose();
    next.dispose();
    confirm.dispose();
    newUsername.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My account'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Username',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: newUsername,
            decoration: const InputDecoration(
              labelText: 'Username',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: saveUsername,
            child: const Text('Save username'),
          ),
          const Divider(height: 40),
          Text(
            'Password',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          PasswordField(
            controller: current,
            label: 'Current password',
          ),
          const SizedBox(height: 14),
          PasswordField(
            controller: next,
            label: 'New password',
          ),
          const SizedBox(height: 14),
          PasswordField(
            controller: confirm,
            label: 'Confirm password',
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: save,
            child: const Text(
              'Change password',
            ),
          ),
        ],
      ),
    );
  }
}

class UsersPage extends StatefulWidget {
  const UsersPage({super.key, required this.api});

  final ApiClient api;

  @override
  State<UsersPage> createState() =>
      _UsersPageState();
}

class _UsersPageState
    extends State<UsersPage> {
  List<dynamic> rows = [];
  bool busy = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      rows = await widget.api.users();
    } catch (_) {}

    if (mounted) {
      setState(() => busy = false);
    }
  }

  Future<void> add() async {
    final username = TextEditingController();
    final password = TextEditingController();
    String role = 'staff';

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: const Text('New user'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: username,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                  ),
                ),
                const SizedBox(height: 14),
                PasswordField(
                  controller: password,
                  label: 'Password',
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'staff', label: Text('Staff')),
                    ButtonSegment(value: 'admin', label: Text('Admin')),
                  ],
                  selected: {role},
                  onSelectionChanged: (s) =>
                      setDialogState(() => role = s.first),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(dialogContext, true),
                child: const Text('Create'),
              ),
            ],
          ),
        );
      },
    );

    if (ok != true) return;

    if (!await BiometricGuard.require(
      context,
      reason: 'Verify your identity before creating a user account.',
    )) return;

    try {
      await widget.api.createUser({
        'username': username.text.trim(),
        'password': password.text,
        'role': role,
      });

      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userFacingError(e))),
        );
      }
    }
  }

  Future<void> changeRole(
    Map<String, dynamic> user,
  ) async {
    final id = user['id'] as int;
    final isPrimary = user['is_primary_admin'] == true;
    final currentRole = '${user['role'] ?? 'staff'}';
    final isAdmin = currentRole == 'admin';

    if (isPrimary) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The original admin must remain an admin.'),
        ),
      );
      return;
    }

    if (isAdmin && !AppSession.isPrimaryAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only the original admin can downgrade another admin.'),
        ),
      );
      return;
    }

    final nextRole = isAdmin ? 'staff' : 'admin';
    final label = nextRole == 'admin'
        ? 'Upgrade ${user['username'] ?? 'user'} to admin?'
        : 'Downgrade ${user['username'] ?? 'user'} to staff?';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(label),
        content: Text(
          nextRole == 'admin'
              ? 'This user will receive admin access.'
              : 'This user will lose admin-only access.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(nextRole == 'admin' ? 'Upgrade' : 'Downgrade'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (!await BiometricGuard.require(
      context,
      reason: 'Verify your identity before changing a user role.',
    )) return;

    try {
      await widget.api.updateUser(
        id,
        {'role': nextRole},
      );
      await load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              nextRole == 'admin'
                  ? 'User upgraded to admin.'
                  : 'User downgraded to staff.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userFacingError(e))),
        );
      }
    }
  }

  Future<void> deleteUser(
    Map<String, dynamic> user,
  ) async {
    if (user['is_primary_admin'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The original admin account cannot be removed.'),
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete user'),
          content: Text(
            'Remove "${user['username'] ?? ''}"?',
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    if (!await BiometricGuard.require(
      context,
      reason: 'Verify your identity before deleting a user account.',
    )) return;

    try {
      await widget.api.deleteUser(
        user['id'] as int,
      );

      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userFacingError(e))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Users'),
        actions: [
          IconButton(
            onPressed: add,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: load,
        child: busy
            ? ListView(
                children: const [
                  SizedBox(height: 160),
                  Center(child: BrandLoader()),
                ],
              )
            : rows.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 160),
                  Center(
                    child: Text('No users found.'),
                  ),
                ],
              )
            : ListView.builder(
                itemCount: rows.length,
                itemBuilder: (_, index) {
                  final user =
                      Map<String, dynamic>.from(
                    rows[index] as Map,
                  );

                  final isPrimary = user['is_primary_admin'] == true;
                  final role = '${user['role'] ?? 'staff'}';
                  return ListTile(
                    leading: Icon(
                      role == 'admin' ? Icons.shield : Icons.person_outline,
                    ),
                    title: Text(
                      '${user['username'] ?? ''}',
                    ),
                    subtitle: Text(
                      isPrimary
                          ? '${role == 'admin' ? 'Admin' : 'Staff'} • Original admin'
                          : (role == 'admin' ? 'Admin' : 'Staff'),
                    ),
                    trailing: isPrimary
                        ? const Tooltip(
                            message: 'The original admin cannot be removed or downgraded',
                            child: Icon(Icons.lock_outline),
                          )
                        : PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'role') {
                                changeRole(user);
                              } else if (value == 'delete') {
                                deleteUser(user);
                              }
                            },
                            itemBuilder: (_) => [
                              if (role == 'staff')
                                const PopupMenuItem(
                                  value: 'role',
                                  child: Text('Upgrade to Admin'),
                                ),
                              if (role == 'admin' && AppSession.isPrimaryAdmin)
                                const PopupMenuItem(
                                  value: 'role',
                                  child: Text('Downgrade to Staff'),
                                ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete user'),
                              ),
                            ],
                          ),
                  );
                },
              ),
      ),
    );
  }
}

class ClearDataPage extends StatefulWidget {
  const ClearDataPage({
    super.key,
    required this.api,
    required this.local,
  });

  final ApiClient api;
  final LocalDatabase local;

  @override
  State<ClearDataPage> createState() =>
      _ClearDataPageState();
}

class _ClearDataPageState
    extends State<ClearDataPage> {
  Future<void> clear() async {
    final confirmation =
        TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'Delete all test data',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'This permanently clears the '
                'test transaction data on the server. '
                'Type the exact confirmation phrase.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmation,
                decoration:
                    const InputDecoration(
                  labelText:
                      'Confirmation phrase',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (ok != true) return;

    if (!await BiometricGuard.require(
      context,
      reason: 'Verify your identity before permanently clearing test data.',
    )) return;

    try {
      await widget.api.clearTestData(
        confirmation: confirmation.text,
      );
      // The server has no way to tell an already-cached phone that these
      // rows are gone (see clearTestDataLocally's doc comment), so wipe the
      // local copies directly — otherwise the Sales tab and the dashboard
      // counts keep showing the deleted data until who-knows-when.
      await widget.local.clearTestDataLocally();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Test data cleared.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userFacingError(e))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Clear test data',
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            const Text(
              'Use this only when you intentionally '
              'want to remove test transaction data.',
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: clear,
              icon: const Icon(
                Icons.delete_forever,
              ),
              label: const Text(
                'Clear test data',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
  });

  final TextEditingController controller;
  final String label;

  @override
  State<PasswordField> createState() =>
      _PasswordFieldState();
}

class _PasswordFieldState
    extends State<PasswordField> {
  bool hidden = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: hidden,
      decoration: InputDecoration(
        labelText: widget.label,
        suffixIcon: IconButton(
          icon: Icon(
            hidden
                ? Icons.visibility
                : Icons.visibility_off,
          ),
          onPressed: () {
            setState(
              () => hidden = !hidden,
            );
          },
        ),
      ),
    );
  }
}
class AuditLogPage extends StatefulWidget {
  const AuditLogPage({super.key, required this.api});
  final ApiClient api;
  @override
  State<AuditLogPage> createState() => _AuditLogPageState();
}

class _AuditLogPageState extends State<AuditLogPage> {
  List<dynamic> rows = [];
  bool busy = true;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final result = await widget.api.auditLog();
      if (mounted) setState(() { rows = result; error = null; });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audit log'),
        actions: [
          IconButton(onPressed: load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: busy
          ? const Center(child: BrandLoader())
          : error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(error!, textAlign: TextAlign.center),
                  ),
                )
              : rows.isEmpty
                  ? const Center(child: Text('No audit entries yet.'))
                  : RefreshIndicator(
                      onRefresh: load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: rows.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, index) {
                          final row = Map<String, dynamic>.from(rows[index] as Map);
                          final detail = row['details'];
                          final subtitle = [
                            (row['username'] ?? 'System').toString(),
                            (row['target_type']?.toString() ?? '') +
                                ' #' +
                                (row['target_id']?.toString() ?? ''),
                            (row['created_at'] ?? '').toString(),
                            if (detail != null) detail.toString(),
                          ].join(' • ');
                          return ListTile(
                            leading: const Icon(Icons.history),
                            title: Text(row['action']?.toString() ?? 'Action'),
                            subtitle: Text(subtitle),
                          );
                        },
                      ),
                    ),
    );
  }
}
