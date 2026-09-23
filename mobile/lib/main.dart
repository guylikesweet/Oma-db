import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'data/api_client.dart';
import 'data/local_database.dart';
import 'data/sync_repository.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalDatabase.instance.db;
  runApp(const OmaMobileApp());
}

class OmaMobileApp extends StatelessWidget {
  const OmaMobileApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Oma Mobile',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
        home: const SessionGate(),
      );
}

class SessionGate extends StatefulWidget {
  const SessionGate({super.key});
  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  final api = ApiClient();
  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
        future: api.token(),
        builder: (_, snapshot) => snapshot.connectionState!= ConnectionState.done
           ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : (snapshot.data?.isNotEmpty == true? HomePage(api: api) : LoginPage(api: api)),
      );
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.api});
  final ApiClient api;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final username = TextEditingController(), password = TextEditingController();
  bool busy = false, obscure = true;
  String? error;
  Future<void> login() async {
    setState(() { busy = true; error = null; });
    try {
      final result = await widget.api.login(username.text.trim(), password.text);
      final token = result['token']?.toString();
      if (token == null || token.isEmpty) throw Exception('Server did not return a token.');
      await widget.api.saveToken(token);
      if (mounted) Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => HomePage(api: widget.api)));
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset('assets/images/logo.png', height: 80),
                  const SizedBox(height: 16),
                  Text('Oma Mobile', style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 28),
                  TextField(controller: username, decoration: const InputDecoration(labelText: 'Username', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(
                      controller: password,
                      obscureText: obscure,
                      decoration: InputDecoration(
                          labelText: 'Password',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                              icon: const Icon(Icons.visibility),
                              onPressed: () => setState(() => obscure =!obscure)))),
                  if (error!= null)
                    Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
                  const SizedBox(height: 20),
                  SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                          onPressed: busy? null : login,
                          child: Text(busy? 'Signing in...' : 'Sign in'))),
                ],
              ),
            ),
          ),
        ),
      );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.api});
  final ApiClient api;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final local = LocalDatabase.instance;
  late final repo = SyncRepository(widget.api, local);
  StreamSubscription<List<ConnectivityResult>>? connectivitySub;
  String status = 'Ready';
  bool busy = false;
  int productCount = 0, salesCount = 0, pending = 0;

  @override
  void initState() {
    super.initState();
    refresh();
    connectivitySub = Connectivity().onConnectivityChanged.listen((_) => sync(silent: true));
  }

  @override
  void dispose() {
    connectivitySub?.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    final db = await local.db;
    final p = await db.rawQuery('SELECT COUNT(*) AS c FROM products');
    final s = await db.rawQuery('SELECT COUNT(*) AS c FROM sales');
    final q = await db.rawQuery("SELECT COUNT(*) AS c FROM sync_queue WHERE status = 'pending'");
    if (mounted) {
      setState(() {
        productCount = (p.first['c'] as int?)?? 0;
        salesCount = (s.first['c'] as int?)?? 0;
        pending = (q.first['c'] as int?)?? 0;
      });
    }
  }

  Future<void> sync({bool silent = false}) async {
    if (busy) return;
    if (!silent) setState(() { busy = true; status = 'Synchronizing...'; });
    try {
      final result = await repo.syncOnce();
      await refresh();
      if (mounted) setState(() => status = 'Synced • ${result.downloaded} changes');
    } catch (_) {
      await refresh();
      if (!silent && mounted) setState(() => status = 'Offline • local work is safe');
    } finally {
      if (!silent && mounted) setState(() => busy = false);
    }
  }

  Future<void> logout() async {
    try { await widget.api.logout(); } catch (_) {}
    await widget.api.clearToken();
    if (mounted) Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => LoginPage(api: widget.api)), (_) => false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Oma Mobile'), actions: [IconButton(onPressed: logout, icon: const Icon(Icons.logout))]),
        body: RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                  child: ListTile(
                      leading: const Icon(Icons.sync),
                      title: Text(status),
                      subtitle: Text(pending == 0? 'No pending offline operations' : '$pending operation(s) waiting to sync'),
                      trailing: IconButton(onPressed: busy? null : () => sync(), icon: const Icon(Icons.sync)))),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _stat(Icons.inventory_2, 'Products', productCount)),
                const SizedBox(width: 12),
                Expanded(child: _stat(Icons.receipt_long, 'Sales', salesCount))
              ]),
              const SizedBox(height: 12),
              FilledButton.icon(
                  onPressed: busy? null : () async { await Navigator.push(context, MaterialPageRoute(builder: (_) => NewSalePage(repo: repo))); await refresh(); },
                  icon: const Icon(Icons.add_shopping_cart),
                  label: const Text('New sale')),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductListPage(local: local))),
                  icon: const Icon(Icons.inventory_2),
                  label: const Text('View products')),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SalesListPage(local: local))),
                  icon: const Icon(Icons.receipt_long),
                  label: const Text('View sales')),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StockPage(local: local, repo: repo))),
                  icon: const Icon(Icons.inventory),
                  label: const Text('Stock adjustments')),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OperationsPage(local: local))),
                  icon: const Icon(Icons.local_shipping),
                  label: const Text('Batches, deliveries & shipping')),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SyncQueuePage(repo: repo, local: local))),
                  icon: const Icon(Icons.cloud_sync),
                  label: const Text('Sync queue & errors')),
            ],
          ),
        ),
      );

  Widget _stat(IconData icon, String label, int value) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [Icon(icon, size: 28), const SizedBox(height: 8), Text('$value', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)), Text(label)]),
        ),
      );
}

class ProductListPage extends StatelessWidget {
  const ProductListPage({super.key, required this.local});
  final LocalDatabase local;
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Products')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
          future: local.db.then((db) => db.query('products', orderBy: 'name ASC')),
          builder: (_, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final rows = snap.data!;
            if (rows.isEmpty) return const Center(child: Text('No products cached yet. Sync when online.'));
            return ListView.builder(
                itemCount: rows.length,
                itemBuilder: (_, i) {
                  final x = rows[i];
                  return ListTile(title: Text('${x['name']}'), subtitle: Text(x['sku']?.toString()?? 'No SKU'), trailing: Text('Stock ${x['stock']}'));
                });
          }));
}

class SalesListPage extends StatelessWidget {
  const SalesListPage({super.key, required this.local});
  final LocalDatabase local;
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Sales')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
          future: local.db.then((db) => db.query('sales', orderBy: 'id DESC')),
          builder: (_, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final rows = snap.data!;
            if (rows.isEmpty) return const Center(child: Text('No sales recorded yet.'));
            return ListView.builder(
                itemCount: rows.length,
                itemBuilder: (_, i) {
                  final x = rows[i];
                  final localOnly = x['local_only'] == 1;
                  return ListTile(
                      leading: Icon(localOnly? Icons.cloud_upload : Icons.receipt_long),
                      title: Text('${x['customer_name']?? 'Customer'}'),
                      subtitle: Text('${x['order_id']?? ''} • ${x['order_status']?? ''}'),
                      trailing: Text(x['total_amount']?.toString()?? '0'));
                });
          }));
}

class NewSalePage extends StatefulWidget {
  const NewSalePage({super.key, required this.repo});
  final SyncRepository repo;
  @override
  State<NewSalePage> createState() => _NewSalePageState();
}

class _NewSalePageState extends State<NewSalePage> {
  final name = TextEditingController(), phone = TextEditingController(), address = TextEditingController(), state = TextEditingController(), notes = TextEditingController();
  List<Map<String, dynamic>> products = [];
  final Map<int, int> qty = {};
  final Map<int, TextEditingController> prices = {};
  bool loading = true, saving = false;
  String payment = 'Paid';

  @override
  void initState() { super.initState(); load(); }

  Future<void> load() async {
    final db = await LocalDatabase.instance.db;
    final rows = await db.query('products', where: 'stock > 0', orderBy: 'name ASC');
    for (final p in rows) { prices[p['id'] as int] = TextEditingController(); }
    if (mounted) setState(() { products = rows; loading = false; });
  }

  @override
  void dispose() {
    for (final c in prices.values) c.dispose();
    for (final c in [name, phone, address, state, notes]) c.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final items = <Map<String, dynamic>>[];
    for (final p in products) {
      final q = qty[p['id'] as int]?? 0;
      if (q > 0) {
        final price = double.tryParse(prices[p['id'] as int]!.text.trim());
        if (price == null || price < 0) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid price for every selected product.')));
          return;
        }
        items.add({'product_id': p['id'], 'qty': q, 'unit_price': price.toStringAsFixed(2)});
      }
    }
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select at least one product.')));
      return;
    }
    setState(() => saving = true);
    try {
      await widget.repo.saveSaleOffline(
          customerName: name.text, customerPhone: phone.text, customerAddress: address.text, customerState: state.text, paymentStatus: payment, notes: notes.text, items: items);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sale saved locally. It will sync automatically when online.')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('New sale')),
      body: loading
         ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(controller: name, decoration: const InputDecoration(labelText: 'Customer name', border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(controller: phone, decoration: const InputDecoration(labelText: 'Phone', border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(controller: address, decoration: const InputDecoration(labelText: 'Address', border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(controller: state, decoration: const InputDecoration(labelText: 'State', border: OutlineInputBorder())),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                    value: payment,
                    decoration: const InputDecoration(labelText: 'Payment status', border: OutlineInputBorder()),
                    items: const [DropdownMenuItem(value: 'Paid', child: Text('Paid')), DropdownMenuItem(value: 'Pending', child: Text('Pending'))],
                    onChanged: (v) { if (v!= null) setState(() => payment = v); }),
                const SizedBox(height: 18),
                const Text('Products', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
               ...products.map((p) {
                  final id = p['id'] as int;
                  final q = qty[id]?? 0;
                  return Card(
                      child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${p['name']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                            Text('Stock: ${p['stock']}'),
                            Row(children: [
                              IconButton(onPressed: q > 0? () => setState(() => qty[id] = q - 1) : null, icon: const Icon(Icons.remove_circle_outline)),
                              Text('$q', style: const TextStyle(fontSize: 18)),
                              IconButton(onPressed: q < (p['stock'] as int)? () => setState(() => qty[id] = q + 1) : null, icon: const Icon(Icons.add_circle_outline)),
                              const SizedBox(width: 12),
                              Expanded(child: TextField(controller: prices[id], keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Unit price', prefixText: '₦', border: OutlineInputBorder())))
                            ])
                          ])));
                }),
                const SizedBox(height: 10),
                TextField(controller: notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notes', border: OutlineInputBorder())),
                const SizedBox(height: 16),
                SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: saving? null : save, icon: const Icon(Icons.save), label: Text(saving? 'Saving...' : 'Save sale offline'))),
              ],
            ));
}

class StockPage extends StatefulWidget {
  const StockPage({super.key, required this.local, required this.repo});
  final LocalDatabase local;
  final SyncRepository repo;
  @override
  State<StockPage> createState() => _StockPageState();
}

class _StockPageState extends State<StockPage> {
  Future<List<Map<String, dynamic>>> load() => widget.local.db.then((db) => db.query('products', orderBy: 'name ASC'));
  Future<void> adjust(Map<String, dynamic> product) async {
    final qty = TextEditingController();
    final reason = TextEditingController(text: 'Mobile stock adjustment');
    final result = await showDialog<List<String>>(
        context: context,
        builder: (c) => AlertDialog(
                title: Text('Adjust ${product['name']}'),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('Current stock: ${product['stock']}'),
                  TextField(controller: qty, keyboardType: const TextInputType.numberWithOptions(signed: true), decoration: const InputDecoration(labelText: 'Change quantity')),
                  TextField(controller: reason, decoration: const InputDecoration(labelText: 'Reason'))
                ]),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
                  FilledButton(onPressed: () => Navigator.pop(c, [qty.text, reason.text]), child: const Text('Save'))
                ]));
    if (result == null) return;
    final change = int.tryParse(result[0]);
    if (change == null || change == 0) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a non-zero whole number.')));
      return;
    }
    try {
      await widget.repo.saveStockAdjustment(productId: product['id'] as int, changeQty: change, reason: result[1]);
      if (mounted) { setState(() {}); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Stock updated locally and queued for sync.'))); }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Stock adjustments')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
          future: load(),
          builder: (_, s) {
            if (!s.hasData) return const Center(child: CircularProgressIndicator());
            return ListView.builder(
                itemCount: s.data!.length,
                itemBuilder: (_, i) {
                  final p = s.data![i];
                  return ListTile(
                      title: Text('${p['name']}'),
                      subtitle: Text(p['sku']?.toString()?? ''),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [Text('${p['stock']}'), IconButton(onPressed: () => adjust(p), icon: const Icon(Icons.edit))]));
                });
          }));
}

class OperationsPage extends StatelessWidget {
  const OperationsPage({super.key, required this.local});
  final LocalDatabase local;
  @override
  Widget build(BuildContext context) => DefaultTabController(
      length: 3,
      child: Scaffold(
          appBar: AppBar(title: const Text('Operations'), bottom: const TabBar(tabs: [Tab(text: 'Batches'), Tab(text: 'Deliveries'), Tab(text: 'Shipping')])),
          body: TabBarView(children: [
            _CachedTable(local: local, table: 'batches', titleKey: 'name', subtitleKey: 'status'),
            _CachedTable(local: local, table: 'deliveries', titleKey: 'method', subtitleKey: 'status'),
            _CachedTable(local: local, table: 'shipping', titleKey: 'courier', subtitleKey: 'shipping_status')
          ])));
}

class _CachedTable extends StatelessWidget {
  const _CachedTable({required this.local, required this.table, required this.titleKey, required this.subtitleKey});
  final LocalDatabase local;
  final String table, titleKey, subtitleKey;
  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(
      future: local.db.then((db) => db.query(table, orderBy: 'id DESC')),
      builder: (_, s) {
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        if (s.data!.isEmpty) return Center(child: Text('No cached $table yet. Sync when online.'));
        return ListView.builder(
            itemCount: s.data!.length,
            itemBuilder: (_, i) {
              final x = s.data![i];
              return ListTile(
                  title: Text(x[titleKey]?.toString().isNotEmpty == true? x[titleKey].toString() : '—'),
                  subtitle: Text(x[subtitleKey]?.toString()?? '—'),
                  trailing: Text('#${x['id']}'));
            });
      });
}

class SyncQueuePage extends StatefulWidget {
  const SyncQueuePage({super.key, required this.repo, required this.local});
  final SyncRepository repo;
  final LocalDatabase local;
  @override
  State<SyncQueuePage> createState() => _SyncQueuePageState();
}

class _SyncQueuePageState extends State<SyncQueuePage> {
  Future<List<Map<String, dynamic>>> load() async => (await widget.local.db).query('sync_queue', orderBy: 'local_id DESC', limit: 100);
  Future<void> retry() async { await widget.repo.retryFailed(); if (mounted) setState(() {}); }
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Sync queue'), actions: [IconButton(onPressed: retry, tooltip: 'Retry failed', icon: const Icon(Icons.replay))]),
        body: FutureBuilder<List<Map<String, dynamic>>>(
            future: load(),
            builder: (_, s) {
              if (!s.hasData) return const Center(child: CircularProgressIndicator());
              final rows = s.data!;
              if (rows.isEmpty) return const Center(child: Text('No queued operations.'));
              return ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (_, i) {
                    final x = rows[i];
                    final status = x['status']?.toString()?? '';
                    final error = x['last_error']?.toString();
                    return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        child: ListTile(
                            leading: Icon(status == 'failed'? Icons.error_outline : status == 'synced'? Icons.cloud_done : Icons.cloud_upload),
                            title: Text(x['operation_type']?.toString()?? 'Operation'),
                            subtitle: Text([status, 'attempts: ${x['attempts']}', if (error!= null && error.isNotEmpty) error].join(' • ')),
                            isThreeLine: error!= null && error.isNotEmpty));
                  });
            }),
      );
}
