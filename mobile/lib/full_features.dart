import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'data/api_client.dart';

class WebsiteFeaturesPage extends StatefulWidget {
  const WebsiteFeaturesPage({super.key, required this.api});

  final ApiClient api;

  @override
  State<WebsiteFeaturesPage> createState() => _WebsiteFeaturesPageState();
}

class _WebsiteFeaturesPageState extends State<WebsiteFeaturesPage> {
  String? error;

  Future<void> open(Widget page) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('All Website Features'),
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
            'Products',
            'Create, edit, delete and stock',
            () => open(ProductsPage(api: widget.api)),
          ),

          _tile(
            Icons.receipt_long,
            'Sales',
            'Sales, status and shipping settlement',
            () => open(SalesPage(api: widget.api)),
          ),

          _tile(
            Icons.inventory,
            'Stock log',
            'Inventory and stock records',
            () => open(
              ReportPage(
                title: 'Inventory Report',
                load: widget.api.inventoryReport,
              ),
            ),
          ),

          _tile(
            Icons.local_shipping,
            'Shipment batches',
            'Create, assign, arrive and settle',
            () => open(BatchesPage(api: widget.api)),
          ),

          _tile(
            Icons.delivery_dining,
            'Deliveries',
            'Ready sales, consolidation, status and labels',
            () => open(DeliveriesPage(api: widget.api)),
          ),

          _tile(
            Icons.track_changes,
            'Shipping',
            'Search shipping and tracking records',
            () => open(ShippingPage(api: widget.api)),
          ),

          _tile(
            Icons.price_change,
            'Rates',
            'Courier and monthly shipping rates',
            () => open(RatesPage(api: widget.api)),
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
            'Business and label settings',
            () => open(SettingsPage(api: widget.api)),
          ),

          _tile(
            Icons.lock_reset,
            'Change password',
            'Update your password',
            () => open(ChangePasswordPage(api: widget.api)),
          ),

          _tile(
            Icons.people,
            'Admin users',
            'Create and remove users',
            () => open(UsersPage(api: widget.api)),
          ),

          _tile(
            Icons.delete_sweep,
            'Clear test data',
            'Confirmation-protected test-data cleanup',
            () => open(ClearDataPage(api: widget.api)),
          ),
        ],
      ),
    );
  }

  Widget _tile(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key, required this.api});

  final ApiClient api;

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
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

class SalesPage extends StatefulWidget {
  const SalesPage({super.key, required this.api});

  final ApiClient api;

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
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
  const BatchesPage({super.key, required this.api});

  final ApiClient api;

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
              sale['order_status'] != 'Cancelled';
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
                (sale) => ListTile(
                  title: Text(
                    '${sale['order_id'] ?? sale['id']}'
                    ' • ${sale['customer_name'] ?? ''}',
                  ),
                  trailing:
                      batch['status'] == 'In Transit'
                          ? IconButton(
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
                            )
                          : null,
                ),
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
    try {
      await widget.api.arriveBatch(id, {});
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
                          batch['status'] == 'In Transit'
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.flight_land,
                                  ),
                                  onPressed: () =>
                                      arriveBatch(
                                    batch['id'] as int,
                                  ),
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

      rows = List<dynamic>.from(results[0] as List);
      readySales = List<dynamic>.from(
        results[1] as List,
      );
    } catch (_) {}

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
        child: rows.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 160),
                  Center(
                    child: Text('No deliveries found.'),
                  ),
                ],
              )
            : ListView.builder(
                itemCount: rows.length,
                itemBuilder: (_, index) {
                  final delivery =
                      Map<String, dynamic>.from(
                    rows[index] as Map,
                  );

                  final count =
                      (delivery['sale_ids'] as List?)
                              ?.length ??
                          0;

                  return Card(
                    child: ListTile(
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
                            value: 'pdf',
                            child: Text(
                              'Share label PDF',
                            ),
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

class ShippingPage extends StatefulWidget {
  const ShippingPage({super.key, required this.api});

  final ApiClient api;

  @override
  State<ShippingPage> createState() =>
      _ShippingPageState();
}

class _ShippingPageState
    extends State<ShippingPage> {
  List<dynamic> rows = [];
  final query = TextEditingController();

  Future<void> load() async {
    try {
      rows = await widget.api.searchShipping(
        trackingNumber: query.text.trim(),
      );
    } catch (_) {}

    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shipping'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: query,
                    onSubmitted: (_) => load(),
                    decoration:
                        const InputDecoration(
                      labelText: 'Tracking number',
                      prefixIcon:
                          Icon(Icons.search),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: load,
                  icon: const Icon(Icons.search),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: load,
              child: rows.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 120),
                        Center(
                          child: Text(
                            'No shipping records found.',
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (_, index) {
                        final shipping =
                            Map<String, dynamic>.from(
                          rows[index] as Map,
                        );

                        return ListTile(
                          title: Text(
                            '${shipping['tracking_number'] ?? 'No tracking'}',
                          ),
                          subtitle: Text(
                            '${shipping['courier'] ?? ''}'
                            ' • ${shipping['shipping_status'] ?? ''}'
                            ' • Sale ${shipping['sale_id'] ?? ''}',
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class RatesPage extends StatelessWidget {
  const RatesPage({super.key, required this.api});

  final ApiClient api;

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
            ),
            _RateList(
              api: api,
              courier: false,
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
  });

  final ApiClient api;
  final bool courier;

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
              trailing: IconButton(
                onPressed: add,
                icon: const Icon(Icons.add),
              ),
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
                  onTap: () => editRate(row),
                  trailing: IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                    ),
                    onPressed: () => deleteRate(row),
                  ),
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
            title: const Text('Sales'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ReportPage(
                  title: 'Sales',
                  load: api.salesReport,
                ),
              ),
            ),
          ),
          ListTile(
            title: const Text('Shipping'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ReportPage(
                  title: 'Shipping',
                  load: api.shippingReport,
                ),
              ),
            ),
          ),
          ListTile(
            title: const Text('Inventory'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ReportPage(
                  title: 'Inventory',
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

class ReportPage extends StatelessWidget {
  const ReportPage({
    super.key,
    required this.title,
    required this.load,
  });

  final String title;
  final Future<dynamic> Function() load;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: FutureBuilder<dynamic>(
        future: load(),
        builder: (_, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '${snapshot.error}',
                ),
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final data = snapshot.data;

          final List<dynamic> list;

          if (data is List) {
            list = data;
          } else if (data is Map &&
              data['sales'] is List) {
            list = List<dynamic>.from(
              data['sales'] as List,
            );
          } else {
            list = [data];
          }

          if (list.isEmpty) {
            return const Center(
              child: Text('No report data.'),
            );
          }

          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (_, index) {
              return Padding(
                padding: const EdgeInsets.all(8),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      '${list[index]}',
                    ),
                  ),
                ),
              );
            },
          );
        },
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Change password'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
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
      await widget.api.createUser({
        'username': username.text.trim(),
        'password': password.text,
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
        title: const Text('Admin users'),
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

                  return ListTile(
                    title: Text(
                      '${user['username'] ?? ''}',
                    ),
                    subtitle: Text(
                      'ID ${user['id'] ?? ''}'
                      ' • ${user['role'] ?? ''}',
                    ),
                    trailing: IconButton(
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
  });

  final ApiClient api;

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
