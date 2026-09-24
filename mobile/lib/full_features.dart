import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
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

  void fail(Object e) => setState(() => error = e.toString());

  Future<void> open(Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('All Website Features')),
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
              Icons.dashboard,
              'Dashboard',
              'KPIs and last 30 days',
              () => open(
                SimpleDataPage(
                  title: 'Dashboard',
                  load: widget.api.dashboard,
                  render: _dashboard,
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
              'Sales, details, status and shipping settlement',
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
              'Create, search and update tracking',
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
              'Create/remove users',
              () => open(UsersPage(api: widget.api)),
            ),
            _tile(
              Icons.delete_sweep,
              'Clear test data',
              'Same confirmation-protected tool as website',
              () => open(ClearDataPage(api: widget.api)),
            ),
          ],
        ),
      );

  Widget _tile(
    IconData icon,
    String title,
    String sub,
    VoidCallback tap,
  ) =>
      Card(
        child: ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(sub),
          trailing: const Icon(Icons.chevron_right),
          onTap: tap,
        ),
      );
}

class SimpleDataPage extends StatelessWidget {
  const SimpleDataPage({
    super.key,
    required this.title,
    required this.load,
    required this.render,
  });

  final String title;
  final Future<Map<String, dynamic>> Function() load;
  final Widget Function(Map<String, dynamic>) render;

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: FutureBuilder<Map<String, dynamic>>(
          future: load(),
          builder: (_, s) {
            if (s.hasError) {
              return Center(child: Text('${s.error}'));
            }

            if (!s.hasData) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            }

            return render(s.data!);
          },
        ),
      );
}

Widget _dashboard(Map<String, dynamic> d) {
  final days = Map<String, dynamic>.from(
    d['last_30_days'] as Map,
  );

  final labels = List<dynamic>.from(
    days['labels'] as List? ?? const [],
  );

  final values = List<dynamic>.from(
    days['values'] as List? ?? const [],
  );

  return ListView(
    padding: const EdgeInsets.all(16),
    children: [
      _kv('Sales today', d['sales_today']),
      _kv('Profit today', d['profit_today']),
      _kv('Pending shipments', d['pending_shipments']),
      _kv('Low stock', d['low_stock_count']),
      const SizedBox(height: 16),
      const Text(
        'Last 30 days',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      ...List.generate(
        labels.length,
        (i) => ListTile(
          title: Text('${labels[i]}'),
          trailing: Text(
            '${i < values.length ? values[i] : 0}',
          ),
        ),
      ),
    ],
  );
}

Widget _kv(String a, Object? b) => Card(
      child: ListTile(
        title: Text(a),
        trailing: Text(
          '${b ?? 0}',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );

class ProductsPage extends StatefulWidget {
  const ProductsPage({
    super.key,
    required this.api,
  });

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
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (ok != true) {
      return;
    }

    try {
      final data = <String, dynamic>{
        'name': name.text,
        'sku': sku.text.isEmpty ? null : sku.text,
        'cost': double.tryParse(cost.text) ?? 0,
      };

      if (old == null) {
        data['stock'] = int.tryParse(stock.text) ?? 0;
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
    final q = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
          'Adjust ${product['name']}',
        ),
        content: TextField(
          controller: q,
          keyboardType:
              const TextInputType.numberWithOptions(
            signed: true,
          ),
          decoration: const InputDecoration(
            labelText: 'Change quantity',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (ok != true) {
      return;
    }

    try {
      await widget.api.stockAdjust({
        'product_id': product['id'],
        'change_qty': int.parse(q.text),
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

  @override
  Widget build(BuildContext context) => Scaffold(
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
                        title: Text('${x['name']}'),
                        subtitle: Text(
                          '${x['sku'] ?? ''} • Stock ${x['stock']}',
                        ),
                        trailing:
                            PopupMenuButton<String>(
                          onSelected: (v) async {
                            if (v == 'edit') {
                              await form(x);
                            }

                            if (v == 'stock') {
                              await adjustStock(x);
                            }

                            if (v == 'delete') {
                              try {
                                await widget.api.deleteProduct(
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
                                      content: Text('$e'),
                                    ),
                                  );
                                }
                              }
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'edit',
                              child: Text('Edit'),
                            ),
                            PopupMenuItem(
                              value: 'stock',
                              child: Text('Adjust stock'),
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

class SalesPage extends StatefulWidget {
  const SalesPage({
    super.key,
    required this.api,
  });

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
      builder: (c) => AlertDialog(
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
                (x) => DropdownMenuItem(
                  value: x,
                  child: Text(x),
                ),
              )
              .toList(),
          onChanged: (x) {
            if (x != null) {
              selected = x;
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (ok != true) {
      return;
    }

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

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Sales')),
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
                    '${x['order_id'] ?? '#${x['id']}'} • '
                    '${x['customer_name'] ?? ''}',
                  ),
                  subtitle: Text(
                    '${x['order_status']} • '
                    '₦${x['total_amount'] ?? 0}',
                  ),
                  trailing:
                      PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v == 'status') {
                        await changeStatus(
                          x['id'] as int,
                        );
                      }

                      if (v == 'settle') {
                        try {
                          await widget.api.settleShipping(
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
                                content: Text('$e'),
                              ),
                            );
                          }
                        }
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'status',
                        child: Text('Update status'),
                      ),
                      if (x['batch_id'] != null &&
                          x['shipping_payment_settled'] != true)
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

class BatchesPage extends StatefulWidget {
  const BatchesPage({
    super.key,
    required this.api,
  });

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
    final n = TextEditingController();
    final notes = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('New shipment batch'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: n,
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
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (ok != true) {
      return;
    }

    try {
      await widget.api.createBatch({
        'name': n.text,
        'notes': notes.text,
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

  Future<void> manage(
    Map<String, dynamic> x,
  ) async {
    try {
      final batch =
          await widget.api.batch(x['id'] as int);

      final sales = List<dynamic>.from(
        batch['sales'] as List? ?? const [],
      );

      final all = await widget.api.sales();

      if (!mounted) {
        return;
      }

      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (sheet) => SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            shrinkWrap: true,
            children: [
              Text(
                '${x['name']} • ${x['status']}',
                style:
                    Theme.of(sheet).textTheme.titleLarge,
              ),
              ...sales.map(
                (s) => ListTile(
                  title: Text(
                    '${s['order_id'] ?? s['id']} • '
                    '${s['customer_name'] ?? ''}',
                  ),
                  trailing: x['status'] == 'In Transit'
                      ? IconButton(
                          icon: const Icon(
                            Icons.remove_circle_outline,
                          ),
                          onPressed: () async {
                            try {
                              await widget.api
                                  .removeSaleFromBatch(
                                x['id'] as int,
                                s['id'] as int,
                                {},
                              );

                              if (sheet.mounted) {
                                Navigator.pop(sheet);
                              }

                              await load();
                            } catch (e) {
                              if (sheet.mounted) {
                                ScaffoldMessenger.of(
                                  sheet,
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
              if (x['status'] == 'In Transit')
                ...all
                    .where(
                      (s) =>
                          s['batch_id'] == null &&
                          s['order_status'] !=
                              'Cancelled',
                    )
                    .take(30)
                    .map(
                      (s) => ListTile(
                        title: Text(
                          'Add ${s['order_id'] ?? s['id']} • '
                          '${s['customer_name'] ?? ''}',
                        ),
                        onTap: () async {
                          try {
                            await widget.api
                                .addSaleToBatch(
                              x['id'] as int,
                              s['id'] as int,
                              {},
                            );

                            if (sheet.mounted) {
                              Navigator.pop(sheet);
                            }

                            await load();
                          } catch (e) {
                            if (sheet.mounted) {
                              ScaffoldMessenger.of(
                                sheet,
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
          ),
        ),
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
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(
          title: const Text('Shipment batches'),
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

            return Card(
              child: ListTile(
                title: Text('${x['name']}'),
                subtitle: Text(
                  '${x['status']} • '
                  '${(x['sale_ids'] as List?)?.length ?? 0} sales',
                ),
                onTap: () => manage(x),
                trailing: x['status'] == 'In Transit'
                    ? IconButton(
                        icon: const Icon(
                          Icons.flight_land,
                        ),
                        onPressed: () async {
                          try {
                            await widget.api.arriveBatch(
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
                                  content: Text('$e'),
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
  List<dynamic> ready = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      rows = await widget.api.deliveries();
      ready = await widget.api.readyDeliveries();
    } catch (_) {}

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> create() async {
    final sales = ready;
    final selected = <int>{};

    final method = TextEditingController(
      text: 'Dispatch Rider',
    );

    final address = TextEditingController();
    final notes = TextEditingController();

    if (sales.isEmpty) {
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

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
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
                ...sales.map(
                  (s) => CheckboxListTile(
                    value: selected.contains(s['id']),
                    title: Text(
                      '${s['order_id'] ?? s['id']} • '
                      '${s['customer_name'] ?? ''}',
                    ),
                    onChanged: (v) => set(
                      () {
                        if (v == true) {
                          selected.add(
                            s['id'] as int,
                          );
                        } else {
                          selected.remove(
                            s['id'] as int,
                          );
                        }
                      },
                    ),
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
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      try {
        await widget.api.createDelivery({
          'sale_ids': selected.toList(),
          'method': method.text,
          'delivery_address': address.text,
          'notes': notes.text,
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
  }

  Future<void> labelData(int id) async {
    final w = TextEditingController();
    final d = TextEditingController();
    final r = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Label package data'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: w,
              decoration: const InputDecoration(
                labelText: 'Weight kg',
              ),
            ),
            TextField(
              controller: d,
              decoration: const InputDecoration(
                labelText: 'Dimensions',
              ),
            ),
            TextField(
              controller: r,
              decoration: const InputDecoration(
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

    if (ok == true) {
      try {
        await widget.api.saveLabelData(
          id,
          {
            'package_weight_kg':
                double.parse(w.text),
            'package_dimensions': d.text,
            'remarks': r.text,
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
  }

  Future<void> sharePdf(int id) async {
    try {
      final bytes = await widget.api.labelPdf(id);

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

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(
          title: const Text('Deliveries'),
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
              rows[i],
            );

            return Card(
              child: ListTile(
                title: Text(
                  'Delivery #${x['id']} • ${x['method']}',
                ),
                subtitle: Text(
                  '${x['status']} • '
                  '${(x['sale_ids'] as List?)?.length ?? 0} sale(s)',
                ),
                trailing:
                    PopupMenuButton<String>(
                  onSelected: (v) async {
                    try {
                      if (v == 'label') {
                        await labelData(
                          x['id'] as int,
                        );
                      } else if (v == 'pdf') {
                        await sharePdf(
                          x['id'] as int,
                        );
                      } else {
                        await widget.api
                            .updateDeliveryStatus(
                          x['id'] as int,
                          {'status': v},
                        );

                        await load();
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(
                          SnackBar(
                            content: Text('$e'),
                          ),
                        );
                      }
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
      );
}

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

  final q = TextEditingController();

  Future<void> load() async {
    try {
      rows = await widget.api.shipping(
        trackingNumber: q.text,
      );
    } catch (_) {}

    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
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
                      controller: q,
                      decoration:
                          const InputDecoration(
                        labelText:
                            'Tracking number',
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
              child: ListView.builder(
                itemCount: rows.length,
                itemBuilder: (_, i) {
                  final x = rows[i];

                  return ListTile(
                    title: Text(
                      '${x['tracking_number'] ?? 'No tracking'}',
                    ),
                    subtitle: Text(
                      '${x['courier'] ?? ''} • '
                      '${x['shipping_status']} • '
                      'Sale ${x['sale_id']}',
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
}

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

class _RateListState
    extends State<_RateList> {
  List<dynamic> rows = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    rows = widget.courier
        ? await widget.api.courierRates()
        : await widget.api.monthlyRates();

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> add() async {
    final a = TextEditingController();
    final b = TextEditingController();

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
              decoration: InputDecoration(
                labelText: widget.courier
                    ? 'State'
                    : 'Month (YYYY-MM-DD)',
              ),
            ),
            TextField(
              controller: b,
              keyboardType:
                  TextInputType.number,
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
      return;
    }

    try {
      if (widget.courier) {
        await widget.api.createCourierRate({
          'state': a.text,
          'rate_per_cbm':
              double.parse(b.text),
        });
      } else {
        await widget.api.createMonthlyRate({
          'month': a.text,
          'rate_per_cbm':
              double.parse(b.text),
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
    Map<String, dynamic> x,
  ) async {
    final a = TextEditingController(
      text: widget.courier
          ? '${x['state']}'
          : '${x['month']}',
    );

    final b = TextEditingController(
      text: '${x['rate_per_cbm']}',
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Edit rate'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: a,
              decoration:
                  const InputDecoration(
                labelText: 'State or month',
              ),
            ),
            TextField(
              controller: b,
              keyboardType:
                  TextInputType.number,
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
      return;
    }

    try {
      if (widget.courier) {
        await widget.api.updateCourierRate(
          x['id'],
          {
            'state': a.text,
            'rate_per_cbm':
                double.parse(b.text),
          },
        );
      } else {
        await widget.api.updateMonthlyRate(
          x['id'],
          {
            'month': a.text,
            'rate_per_cbm':
                double.parse(b.text),
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

  @override
  Widget build(BuildContext context) =>
      Scaffold(
        body: ListView(
          children: [
            ListTile(
              trailing: IconButton(
                onPressed: add,
                icon: const Icon(Icons.add),
              ),
            ),
            ...rows.map(
              (x) => ListTile(
                title: Text(
                  widget.courier
                      ? '${x['state']}'
                      : '${x['month']}',
                ),
                subtitle: Text(
                  '${x['rate_per_cbm']}',
                ),
                onTap: () => editRate(
                  Map<String, dynamic>.from(x),
                ),
                trailing: IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                  ),
                  onPressed: () async {
                    try {
                      if (widget.courier) {
                        await widget.api
                            .deleteCourierRate(
                          x['id'],
                          {},
                        );
                      } else {
                        await widget.api
                            .deleteMonthlyRate(
                          x['id'],
                          {},
                        );
                      }

                      await load();
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(
                          context,
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
            ),
          ],
        ),
      );
}

class ReportsPage extends StatelessWidget {
  const ReportsPage({
    super.key,
    required this.api,
  });

  final ApiClient api;

  @override
  Widget build(BuildContext context) =>
      Scaffold(
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

class ReportPage extends StatelessWidget {
  const ReportPage({
    super.key,
    required this.title,
    required this.load,
  });

  final String title;
  final Future<dynamic> Function() load;

  @override
  Widget build(BuildContext context) =>
      Scaffold(
        appBar: AppBar(
          title: Text(title),
        ),
        body: FutureBuilder<dynamic>(
          future: load(),
          builder: (_, s) {
            if (s.hasError) {
              return Center(
                child: Text('${s.error}'),
              );
            }

            if (!s.hasData) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            }

            final x = s.data;

            final list = x is List
                ? x
                : x is Map &&
                        x['sales'] is List
                    ? x['sales']
                    : <dynamic>[x];

            return ListView.builder(
              itemCount: list.length,
              itemBuilder: (_, i) => Padding(
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
              ),
            );
          },
        ),
      );
}

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
  final name = TextEditingController();
  final phone = TextEditingController();
  final address = TextEditingController();
  final w = TextEditingController();
  final h = TextEditingController();

  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final x = await widget.api.settings();

      name.text =
          '${x['business_name'] ?? ''}';

      phone.text =
          '${x['business_phone'] ?? ''}';

      address.text =
          '${x['business_address'] ?? ''}';

      w.text =
          '${x['label_width_mm'] ?? 100}';

      h.text =
          '${x['label_height_mm'] ?? 150}';
    } catch (_) {}

    if (mounted) {
      setState(() => loading = false);
    }
  }

  Future<void> save() async {
    try {
      await widget.api.updateSettings({
        'business_name': name.text,
        'business_phone': phone.text,
        'business_address': address.text,
        'label_width_mm':
            int.tryParse(w.text),
        'label_height_mm':
            int.tryParse(h.text),
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
  Widget build(BuildContext c) =>
      Scaffold(
        appBar: AppBar(
          title: const Text('Settings'),
        ),
        body: loading
            ? const Center(
                child: CircularProgressIndicator(),
              )
            : ListView(
                padding:
                    const EdgeInsets.all(16),
                children: [
                  TextField(
                    controller: name,
                    decoration:
                        const InputDecoration(
                      labelText: 'Business name',
                    ),
                  ),
                  TextField(
                    controller: phone,
                    decoration:
                        const InputDecoration(
                      labelText: 'Business phone',
                    ),
                  ),
                  TextField(
                    controller: address,
                    decoration:
                        const InputDecoration(
                      labelText: 'Business address',
                    ),
                  ),
                  TextField(
                    controller: w,
                    keyboardType:
                        TextInputType.number,
                    decoration:
                        const InputDecoration(
                      labelText:
                          'Label width (mm)',
                    ),
                  ),
                  TextField(
                    controller: h,
                    keyboardType:
                        TextInputType.number,
                    decoration:
                        const InputDecoration(
                      labelText:
                          'Label height (mm)',
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
  final a = TextEditingController();
  final b = TextEditingController();
  final c = TextEditingController();

  Future<void> save() async {
    if (b.text != c.text) {
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
      final r = await widget.api.changePassword(
        a.text,
        b.text,
      );

      await widget.api.saveToken(
        r['token'].toString(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password changed.'),
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
  Widget build(BuildContext c) =>
      Scaffold(
        appBar: AppBar(
          title: const Text(
            'Change password',
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            PasswordField(
              controller: a,
              label: 'Current password',
            ),
            PasswordField(
              controller: b,
              label: 'New password',
            ),
            PasswordField(
              controller: c,
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
    rows = await widget.api.users();

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> add() async {
    final u = TextEditingController();
    final p = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('New user'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: u,
              decoration:
                  const InputDecoration(
                labelText: 'Username',
              ),
            ),
            PasswordField(
              controller: p,
              label: 'Password',
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

    if (ok == true) {
      try {
        await widget.api.createUser({
          'username': u.text,
          'password': p.text,
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
  }

  @override
  Widget build(BuildContext c) =>
      Scaffold(
        appBar: AppBar(
          title: const Text('Admin users'),
          actions: [
            IconButton(
              onPressed: add,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        body: ListView(
          children: rows
              .map(
                (x) => ListTile(
                  title: Text(
                    '${x['username']}',
                  ),
                  subtitle: Text(
                    'ID ${x['id']}',
                  ),
                  trailing: IconButton(
                    onPressed: () async {
                      try {
                        await widget.api.deleteUser(
                          x['id'],
                          {},
                        );

                        await load();
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(
                            SnackBar(
                              content: Text('$e'),
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(
                      Icons.delete_outline,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      );
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
  Map<String, dynamic>? info;

  @override
  void initState() {
    super.initState();

    widget.api.clearTestDataInfo().then(
      (x) {
        if (mounted) {
          setState(() => info = x);
        }
      },
    );
  }

  Future<void> clear() async {
    final c = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text(
          'Delete all test data',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Products and users are preserved. '
              'Type the exact confirmation phrase.',
            ),
            TextField(
              controller: c,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(d, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(d, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok == true) {
      try {
        await widget.api.clearTestData(
          c.text,
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
  }

  @override
  Widget build(BuildContext c) =>
      Scaffold(
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
              Text(
                'Confirmation: '
                '${info?['confirmation'] ?? 'loading...'}',
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
  Widget build(BuildContext context) =>
      TextField(
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
            onPressed: () => setState(
              () => hidden = !hidden,
            ),
          ),
        ),
      );
}
