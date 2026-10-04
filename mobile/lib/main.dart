import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart' show databaseFactory;
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'brand_loader.dart';
import 'invoice_actions.dart';
import 'login_background.dart';
import 'data/api_client.dart';
import 'data/app_session.dart';
import 'data/local_database.dart';
import 'data/sale_kind.dart';
import 'data/sync_repository.dart';
import 'full_features.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    // Plain sqflite has no browser implementation — this swaps in the
    // IndexedDB-backed factory so the exact same LocalDatabase/SyncRepository
    // code (queries, transactions, the offline sync queue) works unmodified
    // on the web build too, instead of needing a separate web-only data layer.
    databaseFactory = databaseFactoryFfiWeb;
  }
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
        theme: brandTheme(Brightness.light),
        darkTheme: brandTheme(Brightness.dark),
        home: const SessionGate(),
      );
}

// The Omabuy brand: the orange and green are sampled straight from the logo.
const brandOrange = Color(0xFFFC4300);
const brandGreen = Color(0xFF039664);

/// One theme for the whole app: white surfaces, orange for primary actions,
/// green for secondary accents (the logo's own colours).
ThemeData brandTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;

  final scheme = ColorScheme.fromSeed(
    seedColor: brandOrange,
    brightness: brightness,
  ).copyWith(
    primary: brandOrange,
    onPrimary: Colors.white,
    secondary: brandGreen,
    onSecondary: Colors.white,
    surface: dark ? const Color(0xFF121212) : Colors.white,
    onSurface: dark ? Colors.white : const Color(0xFF1F1F1F),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: brandOrange,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      shape: const Border(
        bottom: BorderSide(color: brandOrange, width: 3),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: brandOrange,
      foregroundColor: Colors.white,
    ),
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
              body: Center(child: BrandLoader(label: 'Loading…')),
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
      await AppSession.refresh(widget.api);

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => AppShell(api: widget.api),
          ),
        );
      }
    } catch (e, st) {
      // Temporary: print the full stack trace to the browser console so we
      // can see exactly which line throws, since e.toString() alone gives
      // no location for a null-check (TypeError) failure.
      // ignore: avoid_print
      print('LOGIN ERROR: $e\n$st');
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
        body: Stack(
          children: [
        const Positioned.fill(child: LoginBackground()),
        SafeArea(
          child: LoginPopIn(child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Card(
                  elevation: 10,
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
          )),
        ),
          ],
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

    AppSession.refresh(widget.api);

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
    AppSession.reset();

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
                  tooltip: kIsWeb ? 'Refresh' : 'Sync',
                  onPressed: widget.syncing
                      ? null
                      : () => widget.onSync(silent: false),
                  icon: Icon(kIsWeb ? Icons.refresh : Icons.sync),
                ),
              ],
            ),
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildListDelegate(
                  [
                    // The web build has no real offline mode — nothing is
                    // ever "waiting to sync" there, so this whole card
                    // (which is about the offline queue) is mobile-only.
                    if (!kIsWeb)
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
                          child: BrandLoader(size: 56),
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
                            label: const Text('Preorder sale'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => NewSalePage(
                                  repo: widget.repo,
                                  stocked: true,
                                ),
                              ),
                            ),
                            icon: const Icon(
                              Icons.inventory_2_outlined,
                            ),
                            label: const Text('Stock sale'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
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
                      child: BrandLoader(),
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
  String payment = 'All';
  String saleKind = 'All'; // All, Preorder, Stocked
  DateTimeRange? range;

  // Web-only cache of the live server fetch (see _load below). Filtering
  // on web must not hit the network on every keystroke — only an explicit
  // refresh (opening the page, pull-to-refresh) should do that.
  List<Map<String, dynamic>>? _webRowsCache;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      // Opening this tab is also a good moment to pull anything that
      // happened server-side since the last sync (a deletion via "clear
      // test data", a status change from another device, etc.) — rather
      // than waiting for a connectivity-change event or a manual pull-to-
      // refresh that the person may not think to do.
      widget.repo.syncOnce().then((_) {
        if (mounted) setState(() {});
      }).catchError((_) {});
    }
  }

  bool get _filtered =>
      saleKind != 'All' ||
      status != 'All' ||
      payment != 'All' ||
      range != null ||
      q.isNotEmpty;

  String _d(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1),
      initialDateRange: range,
    );
    if (picked != null) setState(() => range = picked);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Sales'),
          actions: [
            IconButton(
              tooltip: 'New stock sale (OMBSTK-)',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => NewSalePage(
                    repo: widget.repo,
                    stocked: true,
                  ),
                ),
              ).then((_) => setState(() {})),
              icon: const Icon(Icons.inventory_2_outlined),
            ),
            IconButton(
              tooltip: 'New preorder sale',
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
                            'Order, customer, phone or state',
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
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('Type:'),
                  DropdownButton<String>(
                    value: saleKind,
                    items: const ['All', 'Preorder', 'Stocked']
                        .map(
                          (x) => DropdownMenuItem(
                            value: x,
                            child: Text(x),
                          ),
                        )
                        .toList(),
                    onChanged: (v) =>
                        setState(() => saleKind = v ?? 'All'),
                  ),
                  const Text('Payment:'),
                  DropdownButton<String>(
                    value: payment,
                    items: const [
                      'All',
                      'Paid',
                      'Pending',
                      'Refunded',
                    ]
                        .map(
                          (x) => DropdownMenuItem(
                            value: x,
                            child: Text(x),
                          ),
                        )
                        .toList(),
                    onChanged: (v) =>
                        setState(() => payment = v ?? 'All'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _pickRange,
                    icon: const Icon(Icons.date_range),
                    label: Text(
                      range == null
                          ? 'Any date'
                          : '${_d(range!.start)} → ${_d(range!.end)}',
                    ),
                  ),
                  if (_filtered)
                    TextButton(
                      onPressed: () => setState(() {
                        search.clear();
                        q = '';
                        status = 'All';
                        payment = 'All';
                        saleKind = 'All';
                        range = null;
                      }),
                      child: const Text('Clear filters'),
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
                      child: BrandLoader(),
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
                      // Force the next _load() to hit the network again on
                      // web (see _webRowsCache) instead of reusing the
                      // cached fetch — that's the whole point of a manual
                      // refresh.
                      _webRowsCache = null;

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
    List<Map<String, dynamic>> rows;

    if (kIsWeb) {
      // The web build has no real offline mode and keeps no durable local
      // copy (see createSaleOnline) — so it always shows exactly what the
      // server has. Without this, a deletion (e.g. clearing test data)
      // could never be reflected here, since nothing would ever tell a
      // browser tab's local cache that a row it already has is now gone.
      //
      // That fetch is cached for the lifetime of this page, though — the
      // dropdowns and search box below call setState() on every change,
      // which would otherwise re-run this whole method (network call
      // included) on every keystroke. Filtering re-runs freely; fetching
      // only happens once, until _webRowsCache is explicitly cleared by a
      // refresh.
      if (_webRowsCache == null) {
        final remote = await widget.api.sales();
        final fetched = remote
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
        fetched.sort(
          (a, b) => (b['id'] as int? ?? 0).compareTo(a['id'] as int? ?? 0),
        );
        _webRowsCache = fetched;
      }
      rows = List<Map<String, dynamic>>.from(_webRowsCache!);
    } else {
      final db = await widget.local.db;
      rows = await db.query(
        'sales',
        orderBy: 'id DESC',
      );
    }

    if (status != 'All') {
      rows = rows
          .where(
            (x) => x['order_status'] == status,
          )
          .toList();
    }

    if (payment != 'All') {
      rows = rows
          .where((x) => x['payment_status'] == payment)
          .toList();
    }

    if (saleKind != 'All') {
      final wantStocked = saleKind == 'Stocked';
      rows = rows
          .where((x) => isStockSale(x) == wantStocked)
          .toList();
    }

    if (range != null) {
      final start = DateTime(
        range!.start.year,
        range!.start.month,
        range!.start.day,
      );
      final end = DateTime(
        range!.end.year,
        range!.end.month,
        range!.end.day,
        23,
        59,
        59,
      );
      rows = rows.where((x) {
        final d = DateTime.tryParse('${x['sale_date'] ?? ''}');
        // A sale saved offline has no sale_date until it syncs — keep it
        // visible rather than silently hiding a sale you just made.
        if (d == null) return true;
        return !d.isBefore(start) && !d.isAfter(end);
      }).toList();
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
                    .contains(l) ||
                '${x['customer_state'] ?? ''}'
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
  State<SaleDetailPage> createState() => _SaleDetailPageState();
}

class _SaleDetailPageState extends State<SaleDetailPage> {
  Map<String, dynamic>? sale;
  List<Map<String, dynamic>> items = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final db = await widget.local.db;
      final rows = await db.query(
        'sales',
        where: 'id=?',
        whereArgs: [widget.saleId],
        limit: 1,
      );
      if (rows.isEmpty) {
        if (mounted) setState(() => loading = false);
        return;
      }

      var its = await db.query(
        'sale_items',
        where: 'sale_id=?',
        whereArgs: [widget.saleId],
      );

      // Older web/local databases can contain the sale header without its
      // line items. If that happens, hydrate this sale from the server once
      // and cache the complete response locally. This keeps the detail page
      // useful without forcing a full database reset.
      if (its.isEmpty) {
        try {
          final remote = await widget.api.saleDetail(widget.saleId);
          if (remote['id'] != null) {
            await widget.local.upsertSaleFromResponse(
              Map<String, dynamic>.from(remote),
            );
            its = await db.query(
              'sale_items',
              where: 'sale_id=?',
              whereArgs: [widget.saleId],
            );
          }
        } catch (_) {
          // Stay local-first when offline. The empty state below is only
          // shown if the cached sale genuinely has no recoverable items.
        }
      }

      if (mounted) {
        setState(() {
          sale = rows.first;
          items = its;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> shareInvoice() => showInvoiceDialog(
        context,
        widget.api,
        widget.saleId,
        label: '${sale?['order_id'] ?? widget.saleId}',
      );

  Future<void> printInvoice() => showInvoiceDialog(
        context,
        widget.api,
        widget.saleId,
        label: '${sale?['order_id'] ?? widget.saleId}',
      );

  Future<void> status(String value) async {
    try {
      await widget.repo.queueSaleStatus(widget.saleId, value);
      await widget.repo.syncOnce();
      await load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Status updated: $value')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  Future<void> payment(String value) async {
    try {
      if (kIsWeb) {
        await widget.api.updateSaleStatus(
          widget.saleId,
          {'payment_status': value},
        );
      } else {
        await widget.repo.queuePaymentStatus(widget.saleId, value);
        await widget.repo.syncOnce();
      }
      await load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Payment marked: $value')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  Color _statusColor(BuildContext context, String value) {
    final lower = value.toLowerCase();
    if (lower == 'paid' || lower == 'delivered') return Colors.green;
    if (lower == 'cancelled' || lower == 'refunded') return Colors.red;
    if (lower == 'shipped' || lower == 'packed') return Colors.orange;
    return Theme.of(context).colorScheme.primary;
  }

  Widget _pill(BuildContext context, String value, {IconData? icon}) {
    final color = _statusColor(context, value);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(.10),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withOpacity(.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 5),
          ],
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title, {String? action}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          if (action != null)
            Text(
              action,
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }

  Widget _customerCard(BuildContext context, Map<String, dynamic> s) {
    final name = '${s['customer_name'] ?? 'Customer'}';
    final phone = '${s['customer_phone'] ?? ''}'.trim();
    final address = '${s['customer_address'] ?? ''}'.trim();
    final state = '${s['customer_state'] ?? ''}'.trim();
    final city = '${s['customer_city'] ?? ''}'.trim();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  child: Text(
                    name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      if (phone.isNotEmpty)
                        Text(
                          phone,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (address.isNotEmpty || city.isNotEmpty || state.isNotEmpty) ...[
              const Divider(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.location_on_outlined, size: 19),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      [address, city, state]
                          .where((x) => x.isNotEmpty)
                          .join(', '),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                _pill(
                  context,
                  '${s['order_status'] ?? 'New'}',
                  icon: Icons.local_shipping_outlined,
                ),
                _pill(
                  context,
                  '${s['payment_status'] ?? 'Pending'}',
                  icon: Icons.payments_outlined,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _itemCard(BuildContext context, Map<String, dynamic> item) {
    final qty = int.tryParse('${item['qty'] ?? 0}') ?? 0;
    final price = double.tryParse('${item['unit_price'] ?? 0}') ?? 0;
    final total = qty * price;
    final variant = '${item['variant_note'] ?? ''}'.trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(.45),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              color: Theme.of(context).colorScheme.primary.withOpacity(.09),
            ),
            child: Icon(
              Icons.inventory_2_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item['product_name'] ?? 'Product #${item['product_id']}'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  'Qty $qty × ₦${_money(price)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (variant.isNotEmpty)
                  Text(
                    variant,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontStyle: FontStyle.italic,
                        ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '₦${_money(total)}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _totalCard(BuildContext context, Map<String, dynamic> s) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Order total',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  '₦${_money(s['total_amount'])}',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ],
            ),
            if (s['estimated_shipping_cost'] != null) ...[
              const SizedBox(height: 7),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Est. shipping: ₦${_money(s['estimated_shipping_cost'])}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _actionSection(BuildContext context, Map<String, dynamic> s) {
    final currentOrder = '${s['order_status'] ?? 'New'}';
    final currentPayment = '${s['payment_status'] ?? 'Pending'}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(context, 'Order actions'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final x in const ['Packed', 'Shipped', 'Delivered', 'Cancelled'])
              OutlinedButton(
                onPressed: currentOrder == 'Cancelled' || currentOrder == x
                    ? null
                    : () => status(x),
                child: Text(x),
              ),
          ],
        ),
        const SizedBox(height: 14),
        _sectionTitle(context, 'Payment'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final x in const ['Paid', 'Pending', 'Refunded'])
              OutlinedButton.icon(
                onPressed: currentPayment == x ? null : () => payment(x),
                icon: Icon(
                  x == 'Paid'
                      ? Icons.check_circle_outline
                      : x == 'Refunded'
                          ? Icons.undo_outlined
                          : Icons.schedule_outlined,
                  size: 17,
                ),
                label: Text(x),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(child: BrandLoader(label: 'Loading sale…')),
      );
    }

    if (sale == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sale')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.receipt_long_outlined, size: 48),
              const SizedBox(height: 12),
              const Text('Sale not found on this device.'),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: load,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final s = sale!;
    final orderId = '${s['order_id'] ?? 'Sale #${widget.saleId}'}';
    final saleDate = '${s['sale_date'] ?? ''}'.split('T').first;

    return Scaffold(
      appBar: AppBar(
        title: Text(orderId),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Invoice',
            onSelected: (value) {
              if (value == 'share_invoice') shareInvoice();
              if (value == 'print_invoice') printInvoice();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'share_invoice',
                child: Text('Share invoice / receipt'),
              ),
              PopupMenuItem(
                value: 'print_invoice',
                child: Text('Print invoice / receipt'),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
          children: [
            Card(
              clipBehavior: Clip.antiAlias,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(context).colorScheme.primary.withOpacity(.12),
                      Theme.of(context).colorScheme.surface,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                padding: const EdgeInsets.all(17),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SALE',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  letterSpacing: 1.4,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            orderId,
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                          if (saleDate.isNotEmpty)
                            Text(
                              saleDate,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.receipt_long_rounded,
                      size: 42,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _customerCard(context, s),
            const SizedBox(height: 16),
            _sectionTitle(context, 'Items', action: '${items.length} line${items.length == 1 ? '' : 's'}'),
            if (items.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    'No items found for this sale.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              )
            else
              ...items.map((item) => _itemCard(context, item)),
            const SizedBox(height: 8),
            _totalCard(context, s),
            if ('${s['notes'] ?? ''}'.trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              _sectionTitle(context, 'Order note'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(15),
                  child: Text('${s['notes']}'),
                ),
              ),
            ],
            const SizedBox(height: 18),
            _actionSection(context, s),
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

String _naira(double value) {
  final whole = value.round().toString();
  return whole.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
}

class _SaleLine {
  _SaleLine(this.product, {bool stocked = false}) {
    if (stocked) {
      final cost = double.tryParse('${product['cost'] ?? ''}');
      if (cost != null) {
        markup = stockMarkupPercent(cost);
        suggestedPrice = suggestedStockPrice(cost);
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
        toast(e.toString());
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
                      helperText: line.suggestedPrice == null
                          ? null
                          : 'Suggested ₦${_naira(line.suggestedPrice!)} '
                              '(cost + ${line.markup}%)',
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
                child: BrandLoader(),
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
                leading: const Icon(Icons.apps),
                title: const Text('More features'),
                subtitle: const Text(
                  'Batches, deliveries, rates, reports, settings, users, clear test data',
                ),
                trailing:
                    const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => WebsiteFeaturesPage(
                      api: api,
                      local: local,
                    ),
                  ),
                ),
              ),
            ),
            // The offline sync queue only exists on the mobile build now —
            // the web build creates sales directly online, so there's
            // nothing here to show.
            if (!kIsWeb)
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
                title: const Text('My account'),
                subtitle: const Text('Username and password'),
                trailing:
                    const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChangePasswordPage(api: api),
                  ),
                ),
              ),
            ),
            if (!kIsWeb)
            Card(
              child: ListTile(
                leading: const Icon(Icons.sync),
                title: const Text('Sync now'),
                onTap: () => onSync(silent: false),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () async {
                // Ask first, so a stray tap on this button can't sign
                // the user out.
                final sure = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('Log out?'),
                    content: const Text(
                      'Are you sure you want to log out?',
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
                        child: const Text('Log out'),
                      ),
                    ],
                  ),
                );

                if (sure == true) {
                  await onLogout();
                }
              },
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
                child: BrandLoader(),
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
