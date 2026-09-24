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

class OmaMobileApp extends StatefulWidget {
  const OmaMobileApp({super.key});
  @override State<OmaMobileApp> createState() => _OmaMobileAppState();
}

class _OmaMobileAppState extends State<OmaMobileApp> with WidgetsBindingObserver {
  Timer? _timer;
  ThemeMode _theme = ThemeMode.light;

  ThemeMode _themeForNow() {
    final hour = DateTime.now().hour;
    return hour >= 6 && hour < 18 ? ThemeMode.light : ThemeMode.dark;
  }

  void _refreshTheme() {
    final next = _themeForNow();
    if (mounted && next != _theme) setState(() => _theme = next);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _theme = _themeForNow();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _refreshTheme());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshTheme();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Oma Mobile',
        debugShowCheckedModeBanner: false,
        themeMode: _theme,
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: Colors.indigo,
          brightness: Brightness.light,
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: Colors.indigo,
          brightness: Brightness.dark,
        ),
        home: const SessionGate(),
      );
}

class SessionGate extends StatefulWidget {
  const SessionGate({super.key});
  @override State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  final api = ApiClient();

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
        future: api.token(),
        builder: (_, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          return snapshot.data?.isNotEmpty == true
              ? AppShell(api: api)
              : LoginPage(api: api);
        },
      );
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.api});

  final ApiClient api;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final username = TextEditingController();
  final password = TextEditingController();

  bool busy = false;
  bool obscure = true;
  String? error;

  Future<void> login() async {
    if (username.text.trim().isEmpty || password.text.isEmpty) {
      setState(() => error = 'Enter your username and password.');
      return;
    }

    setState(() {
      busy = true;
      error = null;
    });

    try {
      final result = await widget.api.login(
        username.text.trim(),
        password.text,
      );

      final token = result['token']?.toString();

      if (token == null || token.isEmpty) {
        throw Exception('Server did not return an API token.');
      }

      await widget.api.saveToken(token);

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => AppShell(api: widget.api),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          'assets/images/app_icon.png',
                          height: 82,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Oma Mobile',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Full business system • offline capable',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 26),
                        TextField(
                          controller: username,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Username',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: password,
                          obscureText: obscure,
                          onSubmitted: (_) => login(),
                          decoration: InputDecoration(
                            labelText: 'Password',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(
                                obscure
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                              onPressed: () =>
                                  setState(() => obscure = !obscure),
                            ),
                          ),
                        ),
                        if (error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: busy ? null : login,
                            icon: const Icon(Icons.login),
                            label: Text(
                              busy ? 'Signing in...' : 'Sign in',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.api});

  final ApiClient api;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final local = LocalDatabase.instance;

  late final repo = SyncRepository(
    widget.api,
    local,
  );

  StreamSubscription<List<ConnectivityResult>>? connectivity;

  int tab = 0;
  bool syncing = false;
  String syncText = 'Ready';
  int refreshKey = 0;

  @override
  void initState() {
    super.initState();

    connectivity = Connectivity()
        .onConnectivityChanged
        .listen((_) => sync(silent: true));

    sync(silent: true);
  }

  Future<void> sync({bool silent = false}) async {
    if (syncing) return;

    if (mounted) {
      setState(() => syncing = true);
    }

    try {
      final result = await repo.syncOnce();

      if (mounted) {
        setState(() {
          syncText = result.downloaded > 0 || result.completed > 0
              ? 'Synced • ${result.completed} sent, '
                  '${result.downloaded} received'
              : 'Up to date';

          refreshKey++;
        });
      }
    } catch (e) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync unavailable: $e'),
          ),
        );
      }

      if (mounted) {
        setState(() => syncText = 'Offline • local work is safe');
      }
    } finally {
      if (mounted) {
        setState(() => syncing = false);
      }
    }
  }

  Future<void> logout() async {
    await widget.api.clearToken();

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => LoginPage(api: widget.api),
      ),
      (_) => false,
    );
  }

  @override
  void dispose() {
    connectivity?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardPage(
        api: widget.api,
        local: local,
        repo: repo,
        syncText: syncText,
        syncing: syncing,
        onSync: sync,
        refreshKey: refreshKey,
      ),
      SalesPage(
        api: widget.api,
        local: local,
        repo: repo,
        refreshKey: refreshKey,
      ),
      ProductsPage(
        api: widget.api,
        local: local,
        repo: repo,
        refreshKey: refreshKey,
      ),
      StockPage(
        api: widget.api,
        local: local,
        repo: repo,
        refreshKey: refreshKey,
      ),
      MorePage(
        api: widget.api,
        local: local,
        repo: repo,
        onLogout: logout,
        onSync: sync,
        refreshKey: refreshKey,
      ),
    ];

    return Scaffold(
      body: IndexedStack(
        index: tab,
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Sales',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Products',
          ),
          NavigationDestination(
            icon: Icon(Icons.warehouse_outlined),
            selectedIcon: Icon(Icons.warehouse),
            label: 'Stock',
          ),
          NavigationDestination(
            icon: Icon(Icons.more_horiz),
            label: 'More',
          ),
        ],
      ),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.api,
    required this.local,
    required this.repo,
    required this.syncText,
    required this.syncing,
    required this.onSync,
    required this.refreshKey,
  });

  final ApiClient api;
  final LocalDatabase local;
  final SyncRepository repo;
  final String syncText;
  final bool syncing;
  final Future<void> Function({bool silent}) onSync;
  final int refreshKey;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  Map<String, dynamic>? data;
  int pending = 0;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(covariant DashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.refreshKey != widget.refreshKey) {
      load();
    }
  }

  Future<void> load() async {
    try {
      final db = await widget.local.db;

      final products = await db.query('products');
      final sales = await db.query('sales');

      final low = products
          .where((x) => (x['stock'] as int? ?? 0) <= 5)
          .take(8)
          .toList();

      if (mounted) {
        setState(
          () => data = {
            'sales_today': 0,
            'profit_today': 0,
            'pending_shipments': 0,
            'low_stock_count': low.length,
            'low_stock_products': low,
            'local_counts': {
              'products': products.length,
              'sales': sales.length,
            },
          },
        );
      }
    } catch (_) {
      final db = await widget.local.db;

      final p = await db.rawQuery(
        'SELECT COUNT(*) c FROM products',
      );

      final s = await db.rawQuery(
        'SELECT COUNT(*) c FROM sales',
      );

      if (mounted) {
        setState(
          () => data = {
            'sales_today': 0,
            'profit_today': 0,
            'pending_shipments': 0,
            'low_stock_count': 0,
            'low_stock_products': const [],
            'local_counts': {
              'products': p.first['c'],
              'sales': s.first['c'],
            },
          },
        );
      }
    }

    pending = await widget.repo.pendingCount();

    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: () async {
          await widget.onSync(silent: false);
          await load();
        },
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              title: const Text('Oma Dashboard'),
              actions: [
                IconButton(
                  onPressed: widget.syncing
                      ? null
                      : () => widget.onSync(silent: false),
                  icon: const Icon(Icons.sync),
                ),
              ],
            ),
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildListDelegate(
                  [
                    Card(
                      child: ListTile(
                        leading: Icon(
                          widget.syncing
                              ? Icons.sync
                              : Icons.cloud_done,
                        ),
                        title: Text(widget.syncText),
                        subtitle: Text(
                          pending == 0
                              ? 'No pending offline operations'
                              : '$pending operation(s) waiting to sync',
                        ),
                        trailing: widget.syncing
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (data != null)
                      GridView.count(
                        crossAxisCount:
                            MediaQuery.sizeOf(context).width > 600
                                ? 4
                                : 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 1.5,
                        children: [
                          _Kpi(
                            title: 'Sales today',
                            value:
                                '₦${_money(data!['sales_today'])}',
                            icon: Icons.payments,
                          ),
                          _Kpi(
                            title: 'Profit today',
                            value:
                                '₦${_money(data!['profit_today'])}',
                            icon: Icons.trending_up,
                          ),
                          _Kpi(
                            title: 'Pending shipments',
                            value:
                                '${data!['pending_shipments'] ?? 0}',
                            icon: Icons.local_shipping,
                          ),
                          _Kpi(
                            title: 'Low stock',
                            value:
                                '${data!['low_stock_count'] ?? 0}',
                            icon: Icons.warning_amber,
                          ),
                        ],
                      )
                    else
                      const SizedBox(
                        height: 160,
                        child: Center(
                          child: CircularProgressIndicator(),
                        ),
                      ),
                    const SizedBox(height: 16),
                    if ((data?['low_stock_products'] as List?)
                            ?.isNotEmpty ==
                        true)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Low stock',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge,
                              ),
                              const SizedBox(height: 8),
                              ...List<dynamic>.from(
                                data!['low_stock_products'],
                              ).take(8).map(
                                    (x) => ListTile(
                                      contentPadding:
                                          EdgeInsets.zero,
                                      leading: const Icon(
                                        Icons.inventory_2,
                                      ),
                                      title: Text('${x['name']}'),
                                      subtitle: Text(
                                        x['sku']?.toString() ??
                                            'No SKU',
                                      ),
                                      trailing: Text(
                                        '${x['stock']}',
                                      ),
                                    ),
                                  ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Text(
                      'Quick actions',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => NewSalePage(
                                  repo: widget.repo,
                                ),
                              ),
                            ),
                            icon: const Icon(
                              Icons.add_shopping_cart,
                            ),
                            label: const Text('New sale'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => StockPage(
                                  api: widget.api,
                                  local: widget.local,
                                  repo: widget.repo,
                                  refreshKey: widget.refreshKey,
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.add_box),
                            label: const Text('Adjust stock'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}

class _Kpi extends StatelessWidget {
  const _Kpi({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext c) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon),
              const SizedBox(height: 5),
              Text(
                value,
                style: Theme.of(c)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              Text(
                title,
                style: Theme.of(c).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
}

String _money(dynamic x) {
  final n = double.tryParse('$x') ?? 0;

  return n
      .toStringAsFixed(2)
      .replaceAllMapped(
        RegExp(r'(?<=\d)(?=(\d{3})+(?!\d))'),
        (_) => ',',
      );
}

class ProductsPage extends StatefulWidget {
  const ProductsPage({
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
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  final search = TextEditingController();
  String q = '';

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Products'),
          actions: [
            IconButton(
              onPressed: () => _editProduct(context, null),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: search,
                onChanged: (v) => setState(() => q = v.trim()),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search name or SKU',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _load(),
                builder: (_, s) {
                  if (!s.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }

                  final rows = s.data!;

                  if (rows.isEmpty) {
                    return const Center(
                      child: Text('No products found.'),
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: () async {
                      await widget.repo
                          .syncOnce()
                          .catchError(
                            (_) => SyncResult(
                              completed: 0,
                              downloaded: 0,
                              cursor: 0,
                            ),
                          );

                      if (mounted) setState(() {});
                    },
                    child: ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final p = rows[i];

                        return ListTile(
                          leading: CircleAvatar(
                            child: Text('${p['stock'] ?? 0}'),
                          ),
                          title: Text('${p['name']}'),
                          subtitle: Text(
                            '${p['sku'] ?? 'No SKU'} • '
                            '₦${_money(p['cost'])}',
                          ),
                          trailing: IconButton(
                            icon: const Icon(
                              Icons.edit_outlined,
                            ),
                            onPressed: () =>
                                _editProduct(context, p),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );

  Future<List<Map<String, dynamic>>> _load() async {
    final db = await widget.local.db;

    final rows = await db.query(
      'products',
      orderBy: 'name ASC',
    );

    if (q.isEmpty) return rows;

    final l = q.toLowerCase();

    return rows
        .where(
          (x) =>
              '${x['name']}'.toLowerCase().contains(l) ||
              '${x['sku'] ?? ''}'.toLowerCase().contains(l),
        )
        .toList();
  }

  Future<void> _editProduct(
    BuildContext context,
    Map<String, dynamic>? product,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => ProductDialog(
        api: widget.api,
        repo: widget.repo,
        product: product,
      ),
    );

    if (result == true && mounted) {
      setState(() {});
    }
  }
}

class ProductDialog extends StatefulWidget {
  const ProductDialog({
    super.key,
    required this.api,
    required this.repo,
    this.product,
  });

  final ApiClient api;
  final SyncRepository repo;
  final Map<String, dynamic>? product;

  @override
  State<ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends State<ProductDialog> {
  late final name = TextEditingController(
    text: widget.product?['name']?.toString() ?? '',
  );

  late final sku = TextEditingController(
    text: widget.product?['sku']?.toString() ?? '',
  );

  late final cost = TextEditingController(
    text: widget.product?['cost']?.toString() ?? '',
  );

  late final l = TextEditingController(
    text: widget.product?['length_cm']?.toString() ?? '',
  );

  late final w = TextEditingController(
    text: widget.product?['width_cm']?.toString() ?? '',
  );

  late final h = TextEditingController(
    text: widget.product?['height_cm']?.toString() ?? '',
  );

  late final weight = TextEditingController(
    text: widget.product?['actual_weight_kg']?.toString() ?? '',
  );

  late final stock = TextEditingController(
    text: widget.product?['stock']?.toString() ?? '0',
  );

  bool busy = false;
  String? error;

  @override
  void dispose() {
    for (final c in [
      name,
      sku,
      cost,
      l,
      w,
      h,
      weight,
      stock,
    ]) {
      c.dispose();
    }

    super.dispose();
  }

  Future<void> save() async {
    if (name.text.trim().isEmpty) {
      setState(() => error = 'Product name is required.');
      return;
    }

    setState(() => busy = true);

    try {
      if (widget.product == null) {
        await widget.repo.createProductOnline(
          name: name.text,
          sku: sku.text,
          cost: cost.text,
          lengthCm: l.text,
          widthCm: w.text,
          heightCm: h.text,
          actualWeightKg: weight.text,
          stock: int.tryParse(stock.text) ?? 0,
        );
      } else {
        await widget.repo.updateProductOnline(
          widget.product!['id'] as int,
          {
            'name': name.text,
            'sku': sku.text,
            'cost': cost.text,
            'length_cm': l.text,
            'width_cm': w.text,
            'height_cm': h.text,
            'actual_weight_kg': weight.text,
          },
        );
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(
          widget.product == null
              ? 'Add product'
              : 'Edit product',
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration:
                      const InputDecoration(labelText: 'Name'),
                ),
                TextField(
                  controller: sku,
                  decoration:
                      const InputDecoration(labelText: 'SKU'),
                ),
                TextField(
                  controller: cost,
                  keyboardType:
                      const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Cost',
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: l,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Length cm',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: w,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Width cm',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: h,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Height cm',
                        ),
                      ),
                    ),
                  ],
                ),
                TextField(
                  controller: weight,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Actual weight kg',
                  ),
                ),
                if (widget.product == null)
                  TextField(
                    controller: stock,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Opening stock',
                    ),
                  ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color:
                            Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed:
                busy ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: busy ? null : save,
            child: Text(busy ? 'Saving...' : 'Save'),
          ),
        ],
      );
}

class SalesPage extends StatefulWidget {
  const SalesPage({
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
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  final search = TextEditingController();
  String q = '';
  String status = 'All';

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Sales'),
          actions: [
            IconButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => NewSalePage(
                    repo: widget.repo,
                  ),
                ),
              ).then((_) => setState(() {})),
              icon: const Icon(Icons.add_shopping_cart),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: search,
                      onChanged: (v) =>
                          setState(() => q = v.trim()),
                      decoration: const InputDecoration(
                        prefixIcon:
                            Icon(Icons.search),
                        hintText:
                            'Order, customer or phone',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: status,
                    items: const [
                      'All',
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
                    onChanged: (v) =>
                        setState(() => status = v ?? 'All'),
                  ),
                ],
              ),
            ),
            Expanded(
              child:
                  FutureBuilder<List<Map<String, dynamic>>>(
                future: _load(),
                builder: (_, s) {
                  if (!s.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }

                  final rows = s.data!;

                  if (rows.isEmpty) {
                    return const Center(
                      child: Text('No sales found.'),
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: () async {
                      await widget.repo
                          .syncOnce()
                          .catchError(
                            (_) => SyncResult(
                              completed: 0,
                              downloaded: 0,
                              cursor: 0,
                            ),
                          );

                      if (mounted) setState(() {});
                    },
                    child: ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final x = rows[i];

                        return ListTile(
                          title: Text(
                            '${x['order_id'] ?? 'Offline sale'} • '
                            '${x['customer_name'] ?? ''}',
                          ),
                          subtitle: Text(
                            '${x['order_status'] ?? ''} • '
                            '${x['payment_status'] ?? ''} • '
                            '₦${_money(x['total_amount'])}',
                          ),
                          leading: Icon(
                            x['local_only'] == 1
                                ? Icons.cloud_upload
                                : Icons.receipt_long,
                          ),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SaleDetailPage(
                                api: widget.api,
                                local: widget.local,
                                repo: widget.repo,
                                saleId: x['id'] as int,
                              ),
                            ),
                          ).then((_) => setState(() {})),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );

  Future<List<Map<String, dynamic>>> _load() async {
    final db = await widget.local.db;

    var rows = await db.query(
      'sales',
      orderBy: 'id DESC',
    );

    if (status != 'All') {
      rows = rows
          .where(
            (x) => x['order_status'] == status,
          )
          .toList();
    }

    if (q.isNotEmpty) {
      final l = q.toLowerCase();

      rows = rows
          .where(
            (x) =>
                '${x['order_id'] ?? ''}'
                    .toLowerCase()
                    .contains(l) ||
                '${x['customer_name'] ?? ''}'
                    .toLowerCase()
                    .contains(l) ||
                '${x['customer_phone'] ?? ''}'
                    .toLowerCase()
                    .contains(l),
          )
          .toList();
    }

    return rows;
  }
}

class SaleDetailPage extends StatefulWidget {
  const SaleDetailPage({
    super.key,
    required this.api,
    required this.local,
    required this.repo,
    required this.saleId,
  });

  final ApiClient api;
  final LocalDatabase local;
  final SyncRepository repo;
  final int saleId;

  @override
  State<SaleDetailPage> createState() =>
      _SaleDetailPageState();
}

class _SaleDetailPageState extends State<SaleDetailPage> {
  Map<String, dynamic>? sale;
  List<Map<String, dynamic>> items = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final db = await widget.local.db;

    final rows = await db.query(
      'sales',
      where: 'id=?',
      whereArgs: [widget.saleId],
      limit: 1,
    );

    if (rows.isEmpty) return;

    final its = await db.query(
      'sale_items',
      where: 'sale_id=?',
      whereArgs: [widget.saleId],
    );

    if (mounted) {
      setState(() {
        sale = rows.first;
        items = its;
      });
    }
  }

  Future<void> status(String value) async {
    try {
      await widget.repo.queueSaleStatus(
        widget.saleId,
        value,
      );

      await widget.repo.syncOnce();
      await load();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Status queued: $value'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (sale == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final s = sale!;

    return Scaffold(
      appBar: AppBar(
        title: Text('${s['order_id'] ?? 'Sale'}'),
      ),
      body: RefreshIndicator(
        onRefresh: load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${s['customer_name']}',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge,
                    ),
                    Text('${s['customer_phone'] ?? ''}'),
                    Text('${s['customer_address'] ?? ''}'),
                    Text('${s['customer_state'] ?? ''}'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: [
                        Chip(
                          label: Text(
                            '${s['order_status']}',
                          ),
                        ),
                        Chip(
                          label: Text(
                            '${s['payment_status']}',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Items',
              style:
                  Theme.of(context).textTheme.titleLarge,
            ),
            ...items.map(
              (i) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${i['product_name'] ?? 'Product #${i['product_id']}'}',
                ),
                subtitle: Text(
                  'Qty ${i['qty']} • '
                  '₦${_money(i['unit_price'])}',
                ),
                trailing: Text(
                  i['variant_note']?.toString() ?? '',
                ),
              ),
            ),
            Card(
              child: ListTile(
                title: const Text('Total'),
                trailing: Text(
                  '₦${_money(s['total_amount'])}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Update status',
              style:
                  Theme.of(context).textTheme.titleMedium,
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                'Packed',
                'Shipped',
                'Delivered',
                'Cancelled',
              ]
                  .map(
                    (x) => OutlinedButton(
                      onPressed:
                          s['order_status'] == 'Cancelled' ||
                                  s['order_status'] == x
                              ? null
                              : () => status(x),
                      child: Text(x),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class NewSalePage extends StatefulWidget {
  const NewSalePage({
    super.key,
    required this.repo,
  });

  final SyncRepository repo;

  @override
  State<NewSalePage> createState() =>
      _NewSalePageState();
}

class _NewSalePageState extends State<NewSalePage> {
  final name = TextEditingController();
  final phone = TextEditingController();
  final address = TextEditingController();
  final state = TextEditingController();
  final notes = TextEditingController();

  List<Map<String, dynamic>> products = [];

  final Map<int, int> qty = {};
  final Map<int, TextEditingController> prices = {};

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
      where: 'stock>0',
      orderBy: 'name ASC',
    );

    for (final p in rows) {
      prices[p['id'] as int] =
          TextEditingController();
    }

    if (mounted) {
      setState(() {
        products = rows;
        loading = false;
      });
    }
  }

  @override
  void dispose() {
    for (final c in prices.values) {
      c.dispose();
    }

    for (final c in [
      name,
      phone,
      address,
      state,
      notes,
    ]) {
      c.dispose();
    }

    super.dispose();
  }

  Future<void> save() async {
    final items = <Map<String, dynamic>>[];

    for (final p in products) {
      final id = p['id'] as int;
      final q = qty[id] ?? 0;

      if (q > 0) {
        final price =
            double.tryParse(prices[id]!.text.trim());

        if (price == null || price < 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Enter a valid price for every selected product.',
              ),
            ),
          );
          return;
        }

        items.add({
          'product_id': id,
          'qty': q,
          'unit_price': price.toStringAsFixed(2),
        });
      }
    }

    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Select at least one product.',
          ),
        ),
      );
      return;
    }

    setState(() => saving = true);

    try {
      await widget.repo.saveSaleOffline(
        customerName: name.text,
        customerPhone: phone.text,
        customerAddress: address.text,
        customerState: state.text,
        paymentStatus: payment,
        notes: notes.text,
        items: items,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Sale saved offline and queued for sync.',
            ),
          ),
        );

        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('New Sale'),
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
                      labelText: 'Customer name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone',
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
                  TextField(
                    controller: state,
                    decoration: const InputDecoration(
                      labelText: 'State',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: payment,
                    decoration: const InputDecoration(
                      labelText: 'Payment status',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'Paid',
                        child: Text('Paid'),
                      ),
                      DropdownMenuItem(
                        value: 'Pending',
                        child: Text('Pending'),
                      ),
                      DropdownMenuItem(
                        value: 'Refunded',
                        child: Text('Refunded'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => payment = v);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  ...products.map(
                    (p) {
                      final id = p['id'] as int;
                      final q = qty[id] ?? 0;

                      return Card(
                        child: Padding(
                          padding:
                              const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${p['name']}',
                                style: const TextStyle(
                                  fontWeight:
                                      FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Stock: ${p['stock']}',
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    onPressed: q > 0
                                        ? () => setState(
                                              () => qty[id] =
                                                  q - 1,
                                            )
                                        : null,
                                    icon: const Icon(
                                      Icons
                                          .remove_circle_outline,
                                    ),
                                  ),
                                  Text('$q'),
                                  IconButton(
                                    onPressed: q <
                                            (p['stock']
                                                as int)
                                        ? () => setState(
                                              () => qty[id] =
                                                  q + 1,
                                            )
                                        : null,
                                    icon: const Icon(
                                      Icons
                                          .add_circle_outline,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: prices[id],
                                      keyboardType:
                                          const TextInputType
                                              .numberWithOptions(
                                        decimal: true,
                                      ),
                                      decoration:
                                          const InputDecoration(
                                        labelText:
                                            'Unit price',
                                        prefixText: '₦',
                                        border:
                                            OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
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
                    label: Text(
                      saving
                          ? 'Saving...'
                          : 'Save sale offline',
                    ),
                  ),
                ],
              ),
      );
}

class StockPage extends StatefulWidget {
  const StockPage({
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
  State<StockPage> createState() => _StockPageState();
}

class _StockPageState extends State<StockPage> {
  int? selected;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Stock'),
          actions: [
            IconButton(
              onPressed: () => _history(context),
              icon: const Icon(Icons.history),
            ),
          ],
        ),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: widget.local.db.then(
            (db) => db.query(
              'products',
              orderBy: 'stock ASC, name ASC',
            ),
          ),
          builder: (_, s) {
            if (!s.hasData) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            }

            final rows = s.data!;

            return RefreshIndicator(
              onRefresh: () async {
                await widget.repo
                    .syncOnce()
                    .catchError(
                      (_) => SyncResult(
                        completed: 0,
                        downloaded: 0,
                        cursor: 0,
                      ),
                    );

                if (mounted) setState(() {});
              },
              child: ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1),
                itemBuilder: (_, i) {
                  final p = rows[i];

                  return ListTile(
                    title: Text('${p['name']}'),
                    subtitle: Text(
                      '${p['sku'] ?? 'No SKU'} • '
                      'Stock ${p['stock']}',
                    ),
                    leading: CircleAvatar(
                      child: Text('${p['stock']}'),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () =>
                          _adjust(context, p),
                    ),
                  );
                },
              ),
            );
          },
        ),
      );

  Future<void> _adjust(
    BuildContext context,
    Map<String, dynamic> p,
  ) async {
    final q = TextEditingController();
    final reason = TextEditingController(
      text: 'Mobile stock adjustment',
    );

    final result = await showDialog<List<String>>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Adjust ${p['name']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Current stock: ${p['stock']}',
            ),
            TextField(
              controller: q,
              keyboardType:
                  const TextInputType.numberWithOptions(
                signed: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Change quantity',
              ),
            ),
            TextField(
              controller: reason,
              decoration: const InputDecoration(
                labelText: 'Reason',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(c, [q.text, reason.text]),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == null) return;

    final change = int.tryParse(result[0]);

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
      await widget.repo.saveStockAdjustment(
        productId: p['id'] as int,
        changeQty: change,
        reason: result[1],
      );

      if (mounted) {
        setState(() {});

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Stock updated locally and queued.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
          ),
        );
      }
    }
  }

  Future<void> _history(BuildContext context) async {
    final logs =
        await widget.api.stockLog().catchError((_) => []);

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .8,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Stock history',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall,
            ),
            ...logs.map(
              (x) => ListTile(
                title: Text(
                  '${x['change_qty'] > 0 ? '+' : ''}'
                  '${x['change_qty']}',
                ),
                subtitle: Text(
                  '${x['reason'] ?? ''} • '
                  '${x['created_at'] ?? ''}',
                ),
                trailing: Text(
                  'Product #${x['product_id']}',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MorePage extends StatelessWidget {
  const MorePage({
    super.key,
    required this.api,
    required this.local,
    required this.repo,
    required this.onLogout,
    required this.onSync,
    required this.refreshKey,
  });

  final ApiClient api;
  final LocalDatabase local;
  final SyncRepository repo;
  final Future<void> Function() onLogout;
  final Future<void> Function({bool silent}) onSync;
  final int refreshKey;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('More'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading:
                    const Icon(Icons.cloud_sync),
                title: const Text('Sync queue'),
                subtitle: const Text(
                  'Pending, failed and retrying operations',
                ),
                trailing:
                    const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SyncQueuePage(
                      repo: repo,
                      local: local,
                    ),
                  ),
                ),
              ),
            ),
            Card(
              child: ListTile(
                leading:
                    const Icon(Icons.lock_reset),
                title: const Text('Change password'),
                trailing:
                    const Icon(Icons.chevron_right),
                onTap: () => showDialog(
                  context: context,
                  builder: (_) =>
                      ChangePasswordDialog(api: api),
                ),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.sync),
                title: const Text('Sync now'),
                onTap: () => onSync(silent: false),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onLogout,
              icon: const Icon(Icons.logout),
              label: const Text('Log out'),
            ),
          ],
        ),
      );
}

class ChangePasswordDialog extends StatefulWidget {
  const ChangePasswordDialog({
    super.key,
    required this.api,
  });

  final ApiClient api;

  @override
  State<ChangePasswordDialog> createState() =>
      _ChangePasswordDialogState();
}

class _ChangePasswordDialogState
    extends State<ChangePasswordDialog> {
  final current = TextEditingController();
  final next = TextEditingController();
  final confirm = TextEditingController();

  bool busy = false;
  bool obscure = true;
  String? error;

  Future<void> save() async {
    if (next.text.length < 6 ||
        next.text != confirm.text) {
      setState(
        () => error =
            'New passwords must match and be at least 6 characters.',
      );
      return;
    }

    setState(() => busy = true);

    try {
      await widget.api.changePassword(
        current.text,
        next.text,
      );

      if (mounted) {
        Navigator.pop(context);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Password changed successfully.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Change password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: current,
              obscureText: obscure,
              decoration: const InputDecoration(
                labelText: 'Current password',
              ),
            ),
            TextField(
              controller: next,
              obscureText: obscure,
              decoration: const InputDecoration(
                labelText: 'New password',
              ),
            ),
            TextField(
              controller: confirm,
              obscureText: obscure,
              decoration: const InputDecoration(
                labelText: 'Confirm new password',
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () =>
                    setState(() => obscure = !obscure),
                child: Text(
                  obscure
                      ? 'Show passwords'
                      : 'Hide passwords',
                ),
              ),
            ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(
                  color:
                      Theme.of(context).colorScheme.error,
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed:
                busy ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: busy ? null : save,
            child: Text(
              busy ? 'Saving...' : 'Change',
            ),
          ),
        ],
      );
}

class SyncQueuePage extends StatefulWidget {
  const SyncQueuePage({
    super.key,
    required this.repo,
    required this.local,
  });

  final SyncRepository repo;
  final LocalDatabase local;

  @override
  State<SyncQueuePage> createState() =>
      _SyncQueuePageState();
}

class _SyncQueuePageState
    extends State<SyncQueuePage> {
  Future<List<Map<String, dynamic>>> load() async =>
      (await widget.local.db).query(
        'sync_queue',
        orderBy: 'local_id DESC',
        limit: 100,
      );

  Future<void> retry() async {
    await widget.repo.retryFailed();

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Sync queue'),
          actions: [
            IconButton(
              onPressed: retry,
              icon: const Icon(Icons.replay),
            ),
          ],
        ),
        body: FutureBuilder<
            List<Map<String, dynamic>>>(
          future: load(),
          builder: (_, s) {
            if (!s.hasData) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            }

            final rows = s.data!;

            if (rows.isEmpty) {
              return const Center(
                child: Text('No queued operations.'),
              );
            }

            return ListView.builder(
              itemCount: rows.length,
              itemBuilder: (_, i) {
                final x = rows[i];
                final status =
                    x['status']?.toString() ?? '';

                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  child: ListTile(
                    leading: Icon(
                      status == 'failed'
                          ? Icons.error_outline
                          : status == 'synced'
                              ? Icons.cloud_done
                              : Icons.cloud_upload,
                    ),
                    title: Text(
                      x['operation_type']
                              ?.toString() ??
                          'Operation',
                    ),
                    subtitle: Text(
                      [
                        status,
                        'attempts: ${x['attempts']}',
                        if ('${x['last_error'] ?? ''}'
                            .isNotEmpty)
                          x['last_error'],
                      ].join(' • '),
                    ),
                  ),
                );
              },
            );
          },
        ),
      );
}
