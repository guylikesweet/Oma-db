import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'data/api_client.dart';
import 'data/app_session.dart';
import 'data/local_database.dart';
import 'data/sale_kind.dart';

class WebsiteFeaturesPage extends StatefulWidget {
  const WebsiteFeaturesPage({super.key, required this.api, required this.local});

  final ApiClient api;
  final LocalDatabase local;

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
            'Full admin: create, edit, delete and stock (see the Products tab for the everyday offline view)',
            () => open(WebProductsPage(api: widget.api)),
          ),

          _tile(
            Icons.receipt_long,
            'Manage sales',
            'Full admin: status and shipping settlement (see the Sales tab for the everyday offline view)',
            () => open(WebSalesPage(api: widget.api)),
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
            'Create, assign, arrive and settle (marking a batch arrived is admin-only)',
            () => open(BatchesPage(api: widget.api, isAdmin: isAdmin)),
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
            'Courier and monthly shipping rates (editing the monthly rate is admin-only)',
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
                ? 'Business and label settings'
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
            () => open(ChangePasswordPage(api: widget.api)),
          ),

          _tile(
            Icons.people,
            'Users',
            isAdmin
                ? 'Add or remove users, admin or staff'
                : 'Add or remove users — admins only',
            isAdmin
                ? () => open(UsersPage(api: widget.api))
                : _adminOnlySnack,
            locked: !isAdmin,
          ),

          _tile(
            Icons.delete_sweep,
            'Clear test data',
            isAdmin
                ? 'Confirmation-protected test-data cleanup'
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
        subtitle: Text(subtitle),
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
    final name = TextEditingController(
      text: '${old?['name'] ?? ''}',
    );
    final sku = TextEditingController(
      text: '${old?['sku'] ?? ''}',
    );
    final cost = TextEditingController(
      text: '${old?['cost'] ?? ''}',
    );
    final stock = TextEditingController(
      text: '${old?['stock'] ?? 0}',
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            old == null ? 'New product' : 'Edit product',
          ),
          content: SingleChildScrollView(
            child: Column(
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                  ),
                ),
                TextField(
                  controller: sku,
                  decoration: const InputDecoration(
                    labelText: 'SKU',
                  ),
                ),
                TextField(
                  controller: cost,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Cost',
                  ),
                ),
                if (old == null)
                  TextField(
                    controller: stock,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Opening stock',
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
        );
      },
    );

    if (ok != true) return;

    try {
      final data = <String, dynamic>{
        'name': name.text.trim(),
        'sku': sku.text.trim().isEmpty ? null : sku.text.trim(),
        'cost': double.tryParse(cost.text.trim()) ?? 0,
      };

      if (old == null) {
        data['stock'] = int.tryParse(stock.text.trim()) ?? 0;
        await widget.api.createProduct(data);
      } else {
        await widget.api.updateProduct(
          old['id'] as int,
          data,
        );
      }

      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
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
          SnackBar(content: Text('$e')),
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

    try {
      await widget.api.deleteProduct(
        product['id'] as int,
      );
      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
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
              child: CircularProgressIndicator(),
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

class WebSalesPage extends StatefulWidget {
  const WebSalesPage({super.key, required this.api});

  final ApiClient api;

  @override
  State<WebSalesPage> createState() => _WebSalesPageState();
}

class _WebSalesPageState extends State<WebSalesPage> {
  List<dynamic> rows = [];

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
      setState(() {});
    }
  }

  Future<void> changeStatus(int id) async {
    String selected = 'New';

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
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  Future<void> settleShipping(int id) async {
    try {
      await widget.api.settleShipping(id, {});
      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  Future<void> shareInvoice(int id) async {
    try {
      final Uint8List bytes = await widget.api.invoicePdf(id);
      await Share.shareXFiles(
        [
          XFile.fromData(
            bytes,
            mimeType: 'application/pdf',
            name: 'invoice-$id.pdf',
          ),
        ],
        text: 'Invoice / receipt #$id',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  Future<void> printInvoice(int id) async {
    try {
      final Uint8List bytes = await widget.api.invoicePdf(id);
      await Printing.layoutPdf(
        name: 'invoice-$id.pdf',
        onLayout: (_) async => bytes,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales'),
      ),
      body: RefreshIndicator(
        onRefresh: load,
        child: rows.isEmpty
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
                        '${sale['order_status'] ?? ''}'
                        ' • ₦${sale['total_amount'] ?? 0}',
                      ),
                      trailing:
                          PopupMenuButton<String>(
                        onSelected: (value) async {
                          if (value == 'status') {
                            await changeStatus(
                              sale['id'] as int,
                            );
                          }

                          if (value == 'settle') {
                            await settleShipping(
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
                          if (sale['batch_id'] != null &&
                              sale['shipping_payment_settled'] !=
                                  true)
                            const PopupMenuItem(
                              value: 'settle',
                              child: Text(
                                'Settle shipping',
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
      setState(() {});
    }
  }

  Future<void> create() async {
    final name = TextEditingController();
    final notes = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('New shipment batch'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(
                  labelText: 'Name',
                ),
              ),
              TextField(
                controller: notes,
                decoration: const InputDecoration(
                  labelText: 'Notes',
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
              child: const Text('Create'),
            ),
          ],
        );
      },
    );

    if (ok != true) return;

    try {
      await widget.api.createBatch({
        'name': name.text.trim(),
        'notes': notes.text.trim(),
      });

      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
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
          .map((x) => x is int ? x : int.parse('$x')),
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
              !isStockSale(sale); // stocked sales aren't shipped in batches
        }).take(50).toList();

        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            shrinkWrap: true,
            children: [
              Text(
                '${batch['name'] ?? 'Batch'} • '
                '${batch['status'] ?? ''}',
                style: Theme.of(sheetContext)
                    .textTheme
                    .titleLarge,
              ),
              const SizedBox(height: 12),

              if (assigned.isEmpty)
                const ListTile(
                  title: Text(
                    'No sales assigned.',
                  ),
                ),

              ...assigned.map(
                (sale) {
                  final settled =
                      sale['shipping_payment_settled'] == true;
                  final cost = sale['actual_shipping_cost'];
                  final arrived = batch['status'] ==
                      'Arrived - Awaiting Shipping Payment';

                  Widget? trailing;
                  if (batch['status'] == 'In Transit') {
                    trailing = IconButton(
                      icon: const Icon(
                        Icons.remove_circle_outline,
                      ),
                      onPressed: () async {
                        try {
                          await widget.api
                              .removeSaleFromBatch(
                            batch['id'] as int,
                            sale['id'] as int,
                            {
                              'action': 'remove',
                            },
                          );

                          if (sheetContext.mounted) {
                            Navigator.pop(sheetContext);
                          }

                          await load();
                        } catch (e) {
                          if (sheetContext.mounted) {
                            ScaffoldMessenger.of(
                              sheetContext,
                            ).showSnackBar(
                              SnackBar(
                                content: Text('$e'),
                              ),
                            );
                          }
                        }
                      },
                    );
                  } else if (arrived && !settled) {
                    trailing = FilledButton.tonal(
                      onPressed: () => settleFromBatch(
                        sheetContext,
                        sale['id'] as int,
                      ),
                      child: const Text('Settle'),
                    );
                  } else if (settled) {
                    trailing = const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                    );
                  }

                  return ListTile(
                    title: Text(
                      '${sale['order_id'] ?? sale['id']}'
                      ' • ${sale['customer_name'] ?? ''}',
                    ),
                    subtitle: cost == null
                        ? null
                        : Text(
                            settled
                                ? 'Shipping ₦${(cost as num).toStringAsFixed(2)} — settled, ready for delivery'
                                : 'Shipping cost: ₦${(cost as num).toStringAsFixed(2)} — awaiting payment',
                          ),
                    trailing: trailing,
                  );
                },
              ),

              if (batch['status'] == 'In Transit') ...[
                const Divider(),
                const Padding(
                  padding: EdgeInsets.symmetric(
                    vertical: 8,
                  ),
                  child: Text(
                    'Add sales',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ...available.map(
                  (sale) => ListTile(
                    title: Text(
                      'Add ${sale['order_id'] ?? sale['id']}'
                      ' • ${sale['customer_name'] ?? ''}',
                    ),
                    onTap: () async {
                      try {
                        await widget.api.addSaleToBatch(
                          batch['id'] as int,
                          sale['id'] as int,
                          {
                            'action': 'add',
                          },
                        );

                        if (sheetContext.mounted) {
                          Navigator.pop(sheetContext);
                        }

                        await load();
                      } catch (e) {
                        if (sheetContext.mounted) {
                          ScaffoldMessenger.of(
                            sheetContext,
                          ).showSnackBar(
                            SnackBar(
                              content: Text('$e'),
                            ),
                          );
                        }
                      }
                    },
                  ),
                ),
              ],
            ],
          ),
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
          'this batch, using this month\'s rate × each sale\'s CBM, and '
          'locks the batch to "Arrived — Awaiting Shipping Payment". '
          'This cannot be undone.',
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
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  Future<void> settleFromBatch(
    BuildContext sheetContext,
    int saleId,
  ) async {
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
          SnackBar(content: Text('$e')),
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
        child: rows.isEmpty
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
                      title: Text(
                        '${batch['name'] ?? ''}',
                      ),
                      subtitle: Text(
                        '${batch['status'] ?? ''}'
                        ' • $saleCount sales',
                      ),
                      onTap: () => manageBatch(batch),
                      trailing:
                          batch['status'] == 'In Transit' && widget.isAdmin
                              ? TextButton.icon(
                                  icon: const Icon(
                                    Icons.flight_land,
                                  ),
                                  label: const Text(
                                    'Mark arrived',
                                  ),
                                  onPressed: () =>
                                      arriveBatch(
                                    batch['id'] as int,
                                  ),
                                )
                              : batch['status'] == 'In Transit'
                                  ? const Chip(label: Text('Admins only'))
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
  String? loadError;

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

    if (mounted) {
      setState(() {});
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

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Create delivery'),
              content: SingleChildScrollView(
                child: Column(
                  children: [
                    TextField(
                      controller: method,
                      decoration: const InputDecoration(
                        labelText: 'Method',
                      ),
                    ),
                    TextField(
                      controller: address,
                      decoration: const InputDecoration(
                        labelText: 'Delivery address',
                      ),
                    ),
                    TextField(
                      controller: notes,
                      decoration: const InputDecoration(
                        labelText: 'Notes',
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...readySales.map(
                      (sale) => CheckboxListTile(
                        value: selected.contains(
                          sale['id'],
                        ),
                        title: Text(
                          '${sale['order_id'] ?? sale['id']}'
                          ' • ${sale['customer_name'] ?? ''}',
                        ),
                        onChanged: (value) {
                          setDialogState(() {
                            final id =
                                sale['id'] as int;

                            if (value == true) {
                              selected.add(id);
                            } else {
                              selected.remove(id);
                            }
                          });
                        },
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
                  onPressed: selected.isEmpty
                      ? null
                      : () => Navigator.pop(
                            dialogContext,
                            true,
                          ),
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok != true) return;

    try {
      await widget.api.createDelivery({
        'sale_ids': selected.toList(),
        'method': method.text.trim(),
        'delivery_address': address.text.trim(),
        'notes': notes.text.trim(),
      });

      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
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
              TextField(
                controller: dimensions,
                decoration: const InputDecoration(
                  labelText: 'Dimensions',
                ),
              ),
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
          SnackBar(content: Text('$e')),
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
          SnackBar(content: Text('$e')),
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
          SnackBar(content: Text('$e')),
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
          SnackBar(content: Text('$e')),
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
        child: ListView(
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
                        ' • $count sale(s)',
                      ),
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
      SnackBar(content: Text('$e')),
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
              TextField(
                controller: dimensions,
                decoration: const InputDecoration(
                  labelText: 'Dimensions',
                  hintText: 'e.g. 30 x 20 x 15 cm',
                ),
              ),
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
          ? const Center(child: CircularProgressIndicator())
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
              // Not gated to admin — only the monthly rate is sensitive
              // per the owner's request; courier state rates are routine.
              isAdmin: true,
            ),
            _RateList(
              api: api,
              courier: false,
              isAdmin: isAdmin,
            ),
          ],
        ),
      ),
    );
  }
}

class _RateList extends StatefulWidget {
  const _RateList({
    required this.api,
    required this.courier,
    this.isAdmin = false,
  });

  final ApiClient api;
  final bool courier;
  final bool isAdmin;

  @override
  State<_RateList> createState() =>
      _RateListState();
}

class _RateListState extends State<_RateList> {
  List<dynamic> rows = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      rows = widget.courier
          ? await widget.api.courierRates()
          : await widget.api.monthlyRates();
    } catch (_) {}

    if (mounted) {
      setState(() {});
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
                : 'Monthly rate',
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
              TextField(
                controller: rate,
                keyboardType:
                    const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration:
                    const InputDecoration(
                  labelText: 'Rate per CBM',
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

    try {
      if (widget.courier) {
        await widget.api.createCourierRate({
          'state': first.text.trim(),
          'rate_per_cbm': parsedRate,
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
          SnackBar(content: Text('$e')),
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
      text: '${row['rate_per_cbm'] ?? ''}',
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
              TextField(
                controller: rate,
                keyboardType:
                    const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration:
                    const InputDecoration(
                  labelText: 'Rate per CBM',
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
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  Future<void> deleteRate(
    Map<String, dynamic> row,
  ) async {
    try {
      final id = row['id'] as int;

      if (widget.courier) {
        await widget.api.deleteCourierRate(id);
      } else {
        await widget.api.deleteMonthlyRate(id);
      }

      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
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
                    : 'Monthly rates',
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
                    '${row['rate_per_cbm'] ?? 0}',
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
                    child: CircularProgressIndicator(),
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
    } catch (_) {}

    if (mounted) {
      setState(() => loading = false);
    }
  }

  Future<void> save() async {
    try {
      await widget.api.updateSettings({
        'business_name': name.text.trim(),
        'business_phone': phone.text.trim(),
        'business_address': address.text.trim(),
        'label_width_mm':
            int.tryParse(width.text.trim()),
        'label_height_mm':
            int.tryParse(height.text.trim()),
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
          SnackBar(content: Text('$e')),
        );
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
              child: CircularProgressIndicator(),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(
                    labelText: 'Business name',
                  ),
                ),
                TextField(
                  controller: phone,
                  decoration: const InputDecoration(
                    labelText: 'Business phone',
                  ),
                ),
                TextField(
                  controller: address,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Business address',
                  ),
                ),
                TextField(
                  controller: width,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Label width (mm)',
                  ),
                ),
                TextField(
                  controller: height,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Label height (mm)',
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: save,
                  child: const Text(
                    'Save settings',
                  ),
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
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  Future<void> save() async {
    if (next.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'New password must be at least 6 characters.',
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

    try {
      await widget.api.changePassword(
        current.text,
        next.text,
      );

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
          SnackBar(content: Text('$e')),
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
          PasswordField(
            controller: next,
            label: 'New password',
          ),
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
      setState(() {});
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
          SnackBar(content: Text('$e')),
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

    try {
      await widget.api.deleteUser(
        user['id'] as int,
      );

      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
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
        child: rows.isEmpty
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
                            message: 'The original admin cannot be removed',
                            child: Icon(Icons.lock_outline),
                          )
                        : IconButton(
                            onPressed: () =>
                                deleteUser(user),
                            icon: const Icon(
                              Icons.delete_outline,
                            ),
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
          SnackBar(content: Text('$e')),
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
