import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'data/api_client.dart';

/// Full Website Feature parity screen.
///
/// This file contains the larger feature set that mirrors the existing
/// Flask website. It is intentionally separate from main.dart so the main
/// application shell can stay smaller and easier to maintain.
class WebsiteFeaturesPage extends StatefulWidget {
  const WebsiteFeaturesPage({
    super.key,
    required this.api,
  });

  final ApiClient api;

  @override
  State<WebsiteFeaturesPage> createState() =>
      _WebsiteFeaturesPageState();
}

class _WebsiteFeaturesPageState
    extends State<WebsiteFeaturesPage> {
  String? error;

  Future<void> open(Widget page) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => page,
      ),
    );
  }

  void fail(Object e) {
    if (!mounted) return;

    setState(() {
      error = e.toString();
    });
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
                leading: const Icon(
                  Icons.error_outline,
                ),
                title: const Text('Request error'),
                subtitle: Text(error!),
                trailing: IconButton(
                  onPressed: () {
                    setState(() {
                      error = null;
                    });
                  },
                  icon: const Icon(Icons.close),
                ),
              ),
            ),

          _tile(
            Icons.inventory_2,
            'Products',
            'Create, edit, delete and stock',
            () => open(
              ProductsPage(
                api: widget.api,
              ),
            ),
          ),

          _tile(
            Icons.receipt_long,
            'Sales',
            'Sales, details, status and shipping settlement',
            () => open(
              SalesPage(
                api: widget.api,
              ),
            ),
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
            () => open(
              BatchesPage(
                api: widget.api,
              ),
            ),
          ),

          _tile(
            Icons.delivery_dining,
            'Deliveries',
            'Ready sales, consolidation, status and labels',
            () => open(
              DeliveriesPage(
                api: widget.api,
              ),
            ),
          ),

          _tile(
            Icons.track_changes,
            'Shipping',
            'Create, search and update tracking',
            () => open(
              ShippingPage(
                api: widget.api,
              ),
            ),
          ),

          _tile(
            Icons.price_change,
            'Rates',
            'Courier and monthly shipping rates',
            () => open(
              RatesPage(
                api: widget.api,
              ),
            ),
          ),

          _tile(
            Icons.bar_chart,
            'Reports',
            'Sales, shipping and inventory reports',
            () => open(
              ReportsPage(
                api: widget.api,
              ),
            ),
          ),

          _tile(
            Icons.settings,
            'Settings',
            'Business and label settings',
            () => open(
              SettingsPage(
                api: widget.api,
              ),
            ),
          ),

          _tile(
            Icons.lock_reset,
            'Change password',
            'Update your password',
            () => open(
              ChangePasswordPage(
                api: widget.api,
              ),
            ),
          ),

          _tile(
            Icons.people,
            'Admin users',
            'Create and manage users',
            () => open(
              UsersPage(
                api: widget.api,
              ),
            ),
          ),

          _tile(
            Icons.delete_sweep,
            'Clear test data',
            'Confirmation-protected test-data tool',
            () => open(
              ClearDataPage(
                api: widget.api,
              ),
            ),
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
        trailing: const Icon(
          Icons.chevron_right,
        ),
        onTap: onTap,
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
/* PRODUCTS                                                                    */
/* -------------------------------------------------------------------------- */

class ProductsPage extends StatefulWidget {
  const ProductsPage({
    super.key,
    required this.api,
  });

  final ApiClient api;

  @override
  State<ProductsPage> createState() =>
      _ProductsPageState();
}

class _ProductsPageState
    extends State<ProductsPage> {
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
    } catch (e) {
      fail(e);
    }

    if (mounted) {
      setState(() {
        busy = false;
      });
    }
  }

  void fail(Object e) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(e.toString()),
      ),
    );
  }

  Future<void> form([
    Map<String, dynamic>? old,
  ]) async {
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
      builder: (c) => AlertDialog(
        title: Text(
          old == null
              ? 'New product'
              : 'Edit product',
        ),
        content: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: name,
                decoration:
                    const InputDecoration(
                  labelText: 'Name',
                ),
              ),
              TextField(
                controller: sku,
                decoration:
                    const InputDecoration(
                  labelText: 'SKU',
                ),
              ),
              TextField(
                controller: cost,
                keyboardType:
                    const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration:
                    const InputDecoration(
                  labelText: 'Cost',
                ),
              ),
              if (old == null)
                TextField(
                  controller: stock,
                  keyboardType:
                      TextInputType.number,
                  decoration:
                      const InputDecoration(
                    labelText: 'Opening stock',
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(c, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (ok != true) {
      name.dispose();
      sku.dispose();
      cost.dispose();
      stock.dispose();
      return;
    }

    try {
      final data = <String, dynamic>{
        'name': name.text.trim(),
        'sku': sku.text.trim().isEmpty
            ? null
            : sku.text.trim(),
        'cost':
            double.tryParse(cost.text) ?? 0,
      };

      if (old == null) {
        data['stock'] =
            int.tryParse(stock.text) ?? 0;

        await widget.api.createProduct(
          data,
        );
      } else {
        await widget.api.updateProduct(
          old['id'] as int,
          data,
        );
      }

      await load();
    } catch (e) {
      fail(e);
    }

    name.dispose();
    sku.dispose();
    cost.dispose();
    stock.dispose();
  }

  Future<void> adjustStock(
    Map<String, dynamic> product,
  ) async {
    final quantity =
        TextEditingController();

    final reason = TextEditingController(
      text: 'Mobile stock adjustment',
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
          'Adjust ${product['name']}',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Current stock: ${product['stock']}',
            ),
            TextField(
              controller: quantity,
              keyboardType:
                  const TextInputType.numberWithOptions(
                signed: true,
              ),
              decoration:
                  const InputDecoration(
                labelText: 'Change quantity',
              ),
            ),
            TextField(
              controller: reason,
              decoration:
                  const InputDecoration(
                labelText: 'Reason',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(c, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (ok != true) {
      quantity.dispose();
      reason.dispose();
      return;
    }

    try {
      await widget.api.stockAdjust({
        'product_id': product['id'],
        'change_qty':
            int.parse(quantity.text),
        'reason': reason.text.trim(),
      });

      await load();
    } catch (e) {
      fail(e);
    }

    quantity.dispose();
    reason.dispose();
  }

  Future<void> deleteProduct(
    int id,
  ) async {
    final confirmed =
        await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text(
          'Delete product?',
        ),
        content: const Text(
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    try {
      await widget.api.deleteProduct(id);
      await load();
    } catch (e) {
      fail(e);
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
              child: ListView.builder(
                itemCount: rows.length,
                itemBuilder: (_, i) {
                  final x =
                      Map<String, dynamic>.from(
                    rows[i] as Map,
                  );

                  return Card(
                    child: ListTile(
                      title: Text(
                        '${x['name']}',
                      ),
                      subtitle: Text(
                        '${x['sku'] ?? ''} • '
                        'Stock ${x['stock'] ?? 0}',
                      ),
                      trailing:
                          PopupMenuButton<String>(
                        onSelected:
                            (value) async {
                          if (value == 'edit') {
                            await form(x);
                          }

                          if (value == 'stock') {
                            await adjustStock(x);
                          }

                          if (value == 'delete') {
                            await deleteProduct(
                              x['id'] as int,
                            );
                          }
                        },
                        itemBuilder: (_) =>
                            const [
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
                            child: Text(
                              'Delete',
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

/* -------------------------------------------------------------------------- */
/* SALES                                                                       */
/* -------------------------------------------------------------------------- */

class SalesPage extends StatefulWidget {
  const SalesPage({
    super.key,
    required this.api,
  });

  final ApiClient api;

  @override
  State<SalesPage> createState() =>
      _SalesPageState();
}

class _SalesPageState
    extends State<SalesPage> {
  List<dynamic> rows = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      rows = await widget.api.sales();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          SnackBar(
            content: Text(e.toString()),
          ),
        );
      }
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> changeStatus(
    int id,
  ) async {
    String selected = 'New';

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text(
            'Update status',
          ),
          content:
              DropdownButtonFormField<String>(
            initialValue: selected,
            items: const [
              'New',
              'Packed',
              'Shipped',
              'Delivered',
              'Cancelled',
            ]
                .map(
                  (x) => DropdownMenuItem(
                    value: x,
                    child: Text(x),
                  ),
                )
                .toList(),
            onChanged: (x) {
              if (x != null) {
                set(() {
                  selected = x;
                });
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(c, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) {
      return;
    }

    try {
      await widget.api.updateSaleStatus(
        id,
        {
          'status': selected,
        },
      );

      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          SnackBar(
            content: Text(e.toString()),
          ),
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
        child: ListView.builder(
          itemCount: rows.length,
          itemBuilder: (_, i) {
            final x =
                Map<String, dynamic>.from(
              rows[i] as Map,
            );

            return Card(
              child: ListTile(
                title: Text(
                  '${x['order_id'] ?? '#${x['id']}'}'
                  ' • '
                  '${x['customer_name'] ?? ''}',
                ),
                subtitle: Text(
                  '${x['order_status'] ?? ''}'
                  ' • '
                  '₦${x['total_amount'] ?? 0}',
                ),
                trailing:
                    PopupMenuButton<String>(
                  onSelected: (value) async {
                    if (value == 'status') {
                      await changeStatus(
                        x['id'] as int,
                      );
                    }

                    if (value == 'settle') {
                      try {
                        await widget.api
                            .settleShipping(
                          x['id'] as int,
                          {},
                        );

                        await load();
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(
                            SnackBar(
                              content:
                                  Text('$e'),
                            ),
                          );
                        }
                      }
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'status',
                      child: Text(
                        'Update status',
                      ),
                    ),
                    if (x['batch_id'] != null &&
                        x['shipping_payment_settled'] !=
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

/* -------------------------------------------------------------------------- */
/* BATCHES                                                                     */
/* -------------------------------------------------------------------------- */

class BatchesPage extends StatefulWidget {
  const BatchesPage({
    super.key,
    required this.api,
  });

  final ApiClient api;

  @override
  State<BatchesPage> createState() =>
      _BatchesPageState();
}

class _BatchesPageState
    extends State<BatchesPage> {
  List<dynamic> rows = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      rows = await widget.api.batches();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          SnackBar(
            content: Text('$e'),
          ),
        );
      }
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> create() async {
    final name =
        TextEditingController();

    final notes =
        TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text(
          'New shipment batch',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration:
                  const InputDecoration(
                labelText: 'Name',
              ),
            ),
            TextField(
              controller: notes,
              decoration:
                  const InputDecoration(
                labelText: 'Notes',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(c, true),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (ok != true) {
      name.dispose();
      notes.dispose();
      return;
    }

    try {
      await widget.api.createBatch({
        'name': name.text.trim(),
        'notes': notes.text.trim(),
      });

      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          SnackBar(
            content: Text('$e'),
          ),
        );
      }
    }

    name.dispose();
    notes.dispose();
  }

  Future<void> manage(
    Map<String, dynamic> batch,
  ) async {
    try {
      final details =
          await widget.api.batch(
        batch['id'] as int,
      );

      final sales = List<dynamic>.from(
        details['sales'] as List? ??
            const [],
      );

      final all =
          await widget.api.sales();

      if (!mounted) return;

      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (sheet) {
          return SafeArea(
            child: ListView(
              padding:
                  const EdgeInsets.all(16),
              children: [
                Text(
                  '${batch['name']} • '
                  '${batch['status']}',
                  style: Theme.of(sheet)
                      .textTheme
                      .titleLarge,
                ),
                const SizedBox(height: 12),

                ...sales.map(
                  (sale) {
                    return ListTile(
                      title: Text(
                        '${sale['order_id'] ?? sale['id']}'
                        ' • '
                        '${sale['customer_name'] ?? ''}',
                      ),
                      trailing:
                          batch['status'] ==
                                  'In Transit'
                              ? IconButton(
                                  icon: const Icon(
                                    Icons
                                        .remove_circle_outline,
                                  ),
                                  onPressed:
                                      () async {
                                    try {
                                      await widget
                                          .api
                                          .removeSaleFromBatch(
                                        batch['id']
                                            as int,
                                        sale['id']
                                            as int,
                                      );

                                      if (sheet
                                          .mounted) {
                                        Navigator.pop(
                                          sheet,
                                        );
                                      }

                                      await load();
                                    } catch (e) {
                                      if (sheet
                                          .mounted) {
                                        ScaffoldMessenger
                                            .of(
                                          sheet,
                                        ).showSnackBar(
                                          SnackBar(
                                            content:
                                                Text(
                                              '$e',
                                            ),
                                          ),
                                        );
                                      }
                                    }
                                  },
                                )
                              : null,
                    );
                  },
                ),

                if (batch['status'] ==
                    'In Transit')
                  ...all
                      .where(
                        (sale) =>
                            sale['batch_id'] ==
                                null &&
                            sale['order_status'] !=
                                'Cancelled',
                      )
                      .take(30)
                      .map(
                    (sale) {
                      return ListTile(
                        title: Text(
                          'Add '
                          '${sale['order_id'] ?? sale['id']}'
                          ' • '
                          '${sale['customer_name'] ?? ''}',
                        ),
                        onTap: () async {
                          try {
                            await widget.api
                                .addSaleToBatch(
                              batch['id'] as int,
                              sale['id'] as int,
                            );

                            if (sheet.mounted) {
                              Navigator.pop(
                                sheet,
                              );
                            }

                            await load();
                          } catch (e) {
                            if (sheet.mounted) {
                              ScaffoldMessenger
                                  .of(sheet)
                                  .showSnackBar(
                                SnackBar(
                                  content:
                                      Text('$e'),
                                ),
                              );
                            }
                          }
                        },
                      );
                    },
                  ),
              ],
            ),
          );
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          SnackBar(
            content: Text('$e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Shipment batches',
        ),
        actions: [
          IconButton(
            onPressed: create,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: rows.length,
        itemBuilder: (_, i) {
          final x =
              Map<String, dynamic>.from(
            rows[i] as Map,
          );

          final saleIds =
              x['sale_ids'] as List?;

          return Card(
            child: ListTile(
              title: Text(
                '${x['name']}',
              ),
              subtitle: Text(
                '${x['status']} • '
                '${saleIds?.length ?? 0} sales',
              ),
              onTap: () => manage(x),
              trailing:
                  x['status'] == 'In Transit'
                      ? IconButton(
                          icon: const Icon(
                            Icons.flight_land,
                          ),
                          onPressed: () async {
                            try {
                              await widget.api
                                  .arriveBatch(
                                x['id'] as int,
                                {},
                              );

                              await load();
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger
                                    .of(context)
                                    .showSnackBar(
                                  SnackBar(
                                    content:
                                        Text('$e'),
                                  ),
                                );
                              }
                            }
                          },
                        )
                      : null,
            ),
          );
        },
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
/* DELIVERIES                                                                  */
/* -------------------------------------------------------------------------- */

class DeliveriesPage extends StatefulWidget {
  const DeliveriesPage({
    super.key,
    required this.api,
  });

  final ApiClient api;

  @override
  State<DeliveriesPage> createState() =>
      _DeliveriesPageState();
}

class _DeliveriesPageState
    extends State<DeliveriesPage> {
  List<dynamic> rows = [];
  Map<String, dynamic>? ready;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      rows =
          await widget.api.deliveries();

      ready =
          await widget.api.readyDeliveries();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          SnackBar(
            content: Text('$e'),
          ),
        );
      }
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> create() async {
    final sales = List<dynamic>.from(
      ready?['sales'] as List? ??
          const [],
    );

    if (sales.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
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

    final method =
        TextEditingController(
      text: 'Dispatch Rider',
    );

    final address =
        TextEditingController();

    final notes =
        TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) {
        return StatefulBuilder(
          builder: (c, set) {
            return AlertDialog(
              title: const Text(
                'Create delivery',
              ),
              content:
                  SingleChildScrollView(
                child: Column(
                  children: [
                    TextField(
                      controller: method,
                      decoration:
                          const InputDecoration(
                        labelText: 'Method',
                      ),
                    ),
                    TextField(
                      controller: address,
                      decoration:
                          const InputDecoration(
                        labelText:
                            'Delivery address',
                      ),
                    ),
                    TextField(
                      controller: notes,
                      decoration:
                          const InputDecoration(
                        labelText: 'Notes',
                      ),
                    ),
                    ...sales.map(
                      (sale) {
                        final id =
                            sale['id'] as int;

                        return CheckboxListTile(
                          value:
                              selected.contains(
                            id,
                          ),
                          title: Text(
                            '${sale['order_id'] ?? id}'
                            ' • '
                            '${sale['customer_name'] ?? ''}',
                          ),
                          onChanged: (value) {
                            set(() {
                              if (value == true) {
                                selected.add(id);
                              } else {
                                selected.remove(
                                  id,
                                );
                              }
                            });
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () =>
                      Navigator.pop(
                    c,
                    false,
                  ),
                  child:
                      const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: selected.isEmpty
                      ? null
                      : () =>
                          Navigator.pop(
                        c,
                        true,
                      ),
                  child:
                      const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok != true) {
      method.dispose();
      address.dispose();
      notes.dispose();
      return;
    }

    try {
      await widget.api.createDelivery({
        'sale_ids': selected.toList(),
        'method': method.text.trim(),
        'delivery_address':
            address.text.trim(),
        'notes': notes.text.trim(),
      });

      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          SnackBar(
            content: Text('$e'),
          ),
        );
      }
    }

    method.dispose();
    address.dispose();
    notes.dispose();
  }

  Future<void> labelData(
    int id,
  ) async {
    final weight =
        TextEditingController();

    final dimensions =
        TextEditingController();

    final remarks =
        TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text(
          'Label package data',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: weight,
              keyboardType:
                  const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration:
                  const InputDecoration(
                labelText: 'Weight kg',
              ),
            ),
            TextField(
              controller: dimensions,
              decoration:
                  const InputDecoration(
                labelText: 'Dimensions',
              ),
            ),
            TextField(
              controller: remarks,
              decoration:
                  const InputDecoration(
                labelText: 'Remarks',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(c, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (ok != true) {
      weight.dispose();
      dimensions.dispose();
      remarks.dispose();
      return;
    }

    try {
      await widget.api.saveLabelData(
        id,
        {
          'package_weight_kg':
              double.tryParse(
                    weight.text,
                  ) ??
                  0,
          'package_dimensions':
              dimensions.text.trim(),
          'remarks':
              remarks.text.trim(),
        },
      );

      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          SnackBar(
            content: Text('$e'),
          ),
        );
      }
    }

    weight.dispose();
    dimensions.dispose();
    remarks.dispose();
  }

  Future<void> sharePdf(
    int id,
  ) async {
    try {
      final bytes =
          await widget.api.labelPdf(id);

      await Share.shareXFiles(
        [
          XFile.fromData(
            bytes,
            mimeType:
                'application/pdf',
            name:
                'label-$id.pdf',
          ),
        ],
        text:
            'Delivery label #$id',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          SnackBar(
            content: Text('$e'),
          ),
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
        {
          'status': status,
        },
      );

      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          SnackBar(
            content: Text('$e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Deliveries',
        ),
        actions: [
          IconButton(
            onPressed: create,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: rows.length,
        itemBuilder: (_, i) {
          final x =
              Map<String, dynamic>.from(
            rows[i] as Map,
          );

          final saleIds =
              x['sale_ids'] as List?;

          return Card(
            child: ListTile(
              title: Text(
                'Delivery #${x['id']}'
                ' • ${x['method'] ?? ''}',
              ),
              subtitle: Text(
                '${x['status'] ?? ''}'
                ' • ${saleIds?.length ?? 0} sale(s)',
              ),
              trailing:
                  PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'label') {
                    await labelData(
                      x['id'] as int,
                    );
                  } else if (value ==
                      'pdf') {
                    await sharePdf(
                      x['id'] as int,
                    );
                  } else {
                    await updateStatus(
                      x['id'] as int,
                      value,
                    );
                  }
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
                    child: Text(
                      'Delivered',
                    ),
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
    );
  }
}

/* -------------------------------------------------------------------------- */
/* SHIPPING                                                                    */
/* -------------------------------------------------------------------------- */

class ShippingPage extends StatefulWidget {
  const ShippingPage({
    super.key,
    required this.api,
  });

  final ApiClient api;

  @override
  State<ShippingPage> createState() =>
      _ShippingPageState();
}

class _ShippingPageState
    extends State<ShippingPage> {
  List<dynamic> rows = [];

  final query =
      TextEditingController();

  Future<void> load() async {
    try {
      rows =
          await widget.api.searchShipping(
        trackingNumber:
            query.text.trim(),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          SnackBar(
            content: Text('$e'),
          ),
        );
      }
    }

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
        title:
            const Text('Shipping'),
      ),
      body: Column(
        children: [
          Padding(
            padding:
                const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: query,
                    decoration:
                        const InputDecoration(
                      labelText:
                          'Tracking number',
                      border:
                          OutlineInputBorder(),
                    ),
                    onSubmitted: (_) =>
                        load(),
                  ),
                ),
                IconButton(
                  onPressed: load,
                  icon:
                      const Icon(Icons.search),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: rows.length,
              itemBuilder: (_, i) {
                final x =
                    Map<String, dynamic>.from(
                  rows[i] as Map,
                );

                return ListTile(
                  title: Text(
                    '${x['tracking_number'] ?? 'No tracking'}',
                  ),
                  subtitle: Text(
                    '${x['courier'] ?? ''}'
                    ' • '
                    '${x['shipping_status'] ?? ''}'
                    ' • Sale '
                    '${x['sale_id'] ?? ''}',
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
/* RATES                                                                       */
/* -------------------------------------------------------------------------- */

class RatesPage extends StatelessWidget {
  const RatesPage({
    super.key,
    required this.api,
  });

  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title:
              const Text('Shipping rates'),
          bottom:
              const TabBar(
            tabs: [
              Tab(
                text: 'Courier',
              ),
              Tab(
                text: 'Monthly',
              ),
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

class _RateListState
    extends State<_RateList> {
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          SnackBar(
            content: Text('$e'),
          ),
        );
      }
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> add() async {
    final a =
        TextEditingController();

    final b =
        TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
          widget.courier
              ? 'Courier rate'
              : 'Monthly rate',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: a,
              decoration:
                  InputDecoration(
                labelText: widget.courier
                    ? 'State'
                    : 'Month',
              ),
            ),
            TextField(
              controller: b,
              keyboardType:
                  const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration:
                  const InputDecoration(
                labelText:
                    'Rate per CBM',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(c, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (ok != true) {
      a.dispose();
      b.dispose();
      return;
    }

    try {
      if (widget.courier) {
        await widget.api
            .createCourierRate({
          'state': a.text.trim(),
          'rate_per_cbm':
              double.parse(b.text),
        });
      } else {
        await widget.api
            .createMonthlyRate({
          'month': a.text.trim(),
          'rate_per_cbm':
              double.parse(b.text),
        });
      }

      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          SnackBar(
            content: Text('$e'),
          ),
        );
      }
    }

    a.dispose();
    b.dispose();
  }

  Future<void> editRate(
    Map<String, dynamic> x,
  ) async {
    final a =
        TextEditingController(
      text: widget.courier
          ? '${x['state']}'
          : '${x['month']}',
    );

    final b =
        TextEditingController(
      text: '${x['rate_per_cbm']}',
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title:
            const Text('Edit rate'),
        content: Column(
          mainAxisSize:
              MainAxisSize.min,
          children: [
            TextField(
              controller: a,
              decoration:
                  const InputDecoration(
                labelText:
                    'State or month',
              ),
            ),
            TextField(
              controller: b,
              keyboardType:
                  const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration:
                  const InputDecoration(
                labelText:
                    'Rate per CBM',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(c, false),
            child:
                const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(c, true),
            child:
                const Text('Save'),
          ),
        ],
      ),
    );

    if (ok != true) {
      a.dispose();
      b.dispose();
      return;
    }

    try {
      if (widget.courier) {
        await widget.api
            .updateCourierRate(
          x['id'] as int,
          {
            'state': a.text.trim(),
            'rate_per_cbm':
                double.parse(b.text),
          },
        );
      } else {
        await widget.api
            .updateMonthlyRate(
          x['id'] as int,
          {
            'month': a.text.trim(),
            'rate_per_cbm':
                double.parse(b.text),
          },
        );
      }

      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          SnackBar(
            content: Text('$e'),
          ),
        );
      }
    }

    a.dispose();
    b.dispose();
  }

  Future<void> deleteRate(
    Map<String, dynamic> x,
  ) async {
    try {
      if (widget.courier) {
        await widget.api
            .deleteCourierRate(
          x['id'] as int,
        );
      } else {
        await widget.api
            .deleteMonthlyRate(
          x['id'] as int,
        );
      }

      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          SnackBar(
            content: Text('$e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(
        children: [
          ListTile(
            trailing: IconButton(
              onPressed: add,
              icon: const Icon(
                Icons.add,
              ),
            ),
          ),
          ...rows.map(
            (raw) {
              final x =
                  Map<String, dynamic>.from(
                raw as Map,
              );

              return ListTile(
                title: Text(
                  widget.courier
                      ? '${x['state']}'
                      : '${x['month']}',
                ),
                subtitle: Text(
                  '${x['rate_per_cbm']}',
                ),
                onTap: () =>
                    editRate(x),
                trailing: IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                  ),
                  onPressed: () =>
                      deleteRate(x),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
/* REPORTS                                                                     */
/* -------------------------------------------------------------------------- */

class ReportsPage extends StatelessWidget {
  const ReportsPage({
    super.key,
    required this.api,
  });

  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text('Reports'),
      ),
      body: ListView(
        children: [
          ListTile(
            leading:
                const Icon(Icons.bar_chart),
            title:
                const Text('Sales'),
            onTap: () =>
                Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    ReportPage(
                  title: 'Sales',
                  load:
                      api.salesReport,
                ),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(
              Icons.local_shipping,
            ),
            title:
                const Text('Shipping'),
            onTap: () =>
                Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    ReportPage(
                  title: 'Shipping',
                  load:
                      api.shippingReport,
                ),
              ),
            ),
          ),
          ListTile(
            leading:
                const Icon(Icons.inventory),
            title:
                const Text('Inventory'),
            onTap: () =>
                Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    ReportPage(
                  title: 'Inventory',
                  load:
                      api.inventoryReport,
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
  final Future<dynamic> Function()
      load;

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
                padding:
                    const EdgeInsets.all(20),
                child: Text(
                  '${snapshot.error}',
                ),
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(
              child:
                  CircularProgressIndicator(),
            );
          }

          final value =
              snapshot.data;

          final List<dynamic> list;

          if (value is List) {
            list = value;
          } else if (value is Map &&
              value['sales'] is List) {
            list = List<dynamic>.from(
              value['sales'] as List,
            );
          } else if (value is Map &&
              value['rows'] is List) {
            list = List<dynamic>.from(
              value['rows'] as List,
            );
          } else {
            list = [value];
          }

          if (list.isEmpty) {
            return const Center(
              child: Text(
                'No report data.',
              ),
            );
          }

          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (_, i) {
              return Padding(
                padding:
                    const EdgeInsets.all(8),
                child: Card(
                  child: Padding(
                    padding:
                        const EdgeInsets.all(12),
                    child: Text(
                      '${list[i]}',
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

/* -------------------------------------------------------------------------- */
/* SETTINGS                                                                    */
/* -------------------------------------------------------------------------- */

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.api,
  });

  final ApiClient api;

  @override
  State<SettingsPage> createState() =>
      _SettingsPageState();
}

class _SettingsPageState
    extends State<SettingsPage> {
  final name =
      TextEditingController();

  final phone =
      TextEditingController();

  final address =
      TextEditingController();

  final width =
      TextEditingController();

  final height =
      TextEditingController();

  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final x =
          await widget.api.settings();

      name.text =
          '${x['business_name'] ?? ''}';

      phone.text =
          '${x['business_phone'] ?? ''}';

      address.text =
          '${x['business_address'] ?? ''}';

      width.text =
          '${x['label_width_mm'] ?? 100}';

      height.text =
          '${x['label_height_mm'] ?? 150}';
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          SnackBar(
            content: Text('$e'),
          ),
        );
      }
    }

    if (mounted) {
      setState(() {
        loading = false;
      });
    }
  }

  Future<void> save() async {
    try {
      await widget.api.updateSettings({
        'business_name':
            name.text.trim(),
        'business_phone':
            phone.text.trim(),
        'business_address':
            address.text.trim(),
        'label_width_mm':
            int.tryParse(width.text),
        'label_height_mm':
            int.tryParse(height.text),
      });

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          const SnackBar(
            content:
                Text('Settings saved.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          SnackBar(
            content: Text('$e'),
          ),
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
    if (loading) {
      return Scaffold(
        appBar: AppBar(
          title:
              const Text('Settings'),
        ),
        body: const Center(
          child:
              CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title:
            const Text('Settings'),
      ),
      body: ListView(
        padding:
            const EdgeInsets.all(16),
        children: [
          TextField(
            controller: name,
            decoration:
                const InputDecoration(
              labelText:
                  'Business name',
              border:
                  OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: phone,
            decoration:
                const InputDecoration(
              labelText:
                  'Business phone',
              border:
                  OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: address,
            decoration:
                const InputDecoration(
              labelText:
                  'Business address',
              border:
                  OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: width,
            keyboardType:
                TextInputType.number,
            decoration:
                const InputDecoration(
              labelText:
                  'Label width (mm)',
              border:
                  OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: height,
            keyboardType:
                TextInputType.number,
            decoration:
                const InputDecoration(
              labelText:
                  'Label height (mm)',
              border:
                  OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: save,
            child:
                const Text('Save settings'),
          ),
        ],
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
/* CHANGE PASSWORD                                                             */
/* -------------------------------------------------------------------------- */

class ChangePasswordPage
    extends StatefulWidget {
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
  final current =
      TextEditingController();

  final next =
      TextEditingController();

  final confirm =
      TextEditingController();

  bool busy = false;

  Future<void> save() async {
    if (next.text.length < 6) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'New password must be at least 6 characters.',
          ),
        ),
      );
      return;
    }

    if (next.text != confirm.text) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'New passwords do not match.',
          ),
        ),
      );
      return;
    }

    setState(() {
      busy = true;
    });

    try {
      await widget.api.changePassword(
        current.text,
        next.text,
      );

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          const SnackBar(
            content:
                Text('Password changed.'),
          ),
        );

        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          SnackBar(
            content: Text('$e'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
        });
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
        title:
            const Text('Change password'),
      ),
      body: ListView(
        padding:
            const EdgeInsets.all(16),
        children: [
          PasswordField(
            controller: current,
            label:
                'Current password',
          ),
          const SizedBox(height: 12),
          PasswordField(
            controller: next,
            label:
                'New password',
          ),
          const SizedBox(height: 12),
          PasswordField(
            controller: confirm,
            label:
                'Confirm password',
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed:
                busy ? null : save,
            child: Text(
              busy
                  ? 'Changing...'
                  : 'Change password',
            ),
          ),
        ],
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
/* USERS                                                                       */
/* -------------------------------------------------------------------------- */

class UsersPage extends StatefulWidget {
  const UsersPage({
    super.key,
    required this.api,
  });

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
      rows =
          await widget.api.users();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          SnackBar(
            content: Text('$e'),
          ),
        );
      }
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> add() async {
    final username =
        TextEditingController();

    final password =
        TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title:
            const Text('New user'),
        content: Column(
          mainAxisSize:
              MainAxisSize.min,
          children: [
            TextField(
              controller: username,
              decoration:
                  const InputDecoration(
                labelText:
                    'Username',
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
                Navigator.pop(c, false),
            child:
                const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(c, true),
            child:
                const Text('Create'),
          ),
        ],
      ),
    );

    if (ok != true) {
      username.dispose();
      password.dispose();
      return;
    }

    try {
      await widget.api.createUser({
        'username':
            username.text.trim(),
        'password':
            password.text,
      });

      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          SnackBar(
            content: Text('$e'),
          ),
        );
      }
    }

    username.dispose();
    password.dispose();
  }

  Future<void> deleteUser(
    int id,
  ) async {
    final ok =
        await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text(
          'Remove user?',
        ),
        content: const Text(
          'The server will enforce the account permissions for this action.',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(c, false),
            child:
                const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(c, true),
            child:
                const Text('Remove'),
          ),
        ],
      ),
    );

    if (ok != true) {
      return;
    }

    try {
      await widget.api.deleteUser(id);
      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          SnackBar(
            content: Text('$e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text('Admin users'),
        actions: [
          IconButton(
            onPressed: add,
            icon:
                const Icon(Icons.add),
          ),
        ],
      ),
      body: ListView(
        children: rows.map(
          (raw) {
            final x =
                Map<String, dynamic>.from(
              raw as Map,
            );

            return ListTile(
              title: Text(
                '${x['username']}',
              ),
              subtitle: Text(
                'ID ${x['id']}'
                '${x['role'] != null ? ' • ${x['role']}' : ''}',
              ),
              trailing: IconButton(
                onPressed: () =>
                    deleteUser(
                  x['id'] as int,
                ),
                icon: const Icon(
                  Icons.delete_outline,
                ),
              ),
            );
          },
        ).toList(),
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
/* CLEAR TEST DATA                                                             */
/* -------------------------------------------------------------------------- */

class ClearDataPage
    extends StatefulWidget {
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
  Map<String, dynamic>? info;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      info = await widget.api
          .clearTestDataInfo();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          SnackBar(
            content: Text('$e'),
          ),
        );
      }
    }

    if (mounted) {
      setState(() {
        loading = false;
      });
    }
  }

  Future<void> clear() async {
    final confirmation =
        TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) =>
          AlertDialog(
        title: const Text(
          'Delete all test data',
        ),
        content: Column(
          mainAxisSize:
              MainAxisSize.min,
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            const Text(
              'This is a destructive operation. '
              'Only use it when you intentionally want '
              'to clear test data.',
            ),
            const SizedBox(height: 12),
            Text(
              'Required confirmation: '
              '${info?['confirmation'] ?? 'loading...'}',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmation,
              decoration:
                  const InputDecoration(
                labelText:
                    'Type confirmation',
                border:
                    OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(
              dialogContext,
              false,
            ),
            child:
                const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(
              dialogContext,
              true,
            ),
            child:
                const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true) {
      confirmation.dispose();
      return;
    }

    try {
      await widget.api.clearTestData(
        confirmation:
            confirmation.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          const SnackBar(
            content: Text(
              'Test data cleared.',
            ),
          ),
        );
      }

      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          SnackBar(
            content: Text('$e'),
          ),
        );
      }
    }

    confirmation.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            'Clear test data',
          ),
        ),
        body: const Center(
          child:
              CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Clear test data',
        ),
      ),
      body: Padding(
        padding:
            const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.warning_amber,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              'Destructive action',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Use the same confirmation-protected '
              'test-data operation provided by the website.',
            ),
            const SizedBox(height: 16),
            Text(
              'Confirmation: '
              '${info?['confirmation'] ?? 'Unavailable'}',
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

/* -------------------------------------------------------------------------- */
/* PASSWORD FIELD                                                              */
/* -------------------------------------------------------------------------- */

class PasswordField
    extends StatefulWidget {
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
      controller:
          widget.controller,
      obscureText: hidden,
      decoration: InputDecoration(
        labelText: widget.label,
        border:
            const OutlineInputBorder(),
        suffixIcon: IconButton(
          icon: Icon(
            hidden
                ? Icons.visibility
                : Icons.visibility_off,
          ),
          onPressed: () {
            setState(() {
              hidden = !hidden;
            });
          },
        ),
      ),
    );
  }
}
