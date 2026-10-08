import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart' show databaseFactory;
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'brand_loader.dart';
import 'invoice_actions.dart';
import 'login_background.dart';
import 'data/api_client.dart';
import 'core/network_errors.dart';
import 'data/app_session.dart';
import 'data/background_sync.dart';
import 'data/local_database.dart';
import 'data/sale_kind.dart';
import 'data/sync_repository.dart';
import 'core/theme_controller.dart';
import 'core/biometric_guard.dart';
import 'core/push_notifications.dart';
import 'theme_settings_page.dart';
import 'full_features.dart';
import 'new_sale_page.dart';
import 'journey_widgets.dart';
import 'chat_page.dart';
import 'profile_page.dart';
import 'presentation/controllers/dashboard_controller.dart';
import 'presentation/controllers/session_controller.dart';
import 'presentation/providers/app_providers.dart';

@pragma('vm:entry-point')
Future<void> omaFirebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await OmaPushNotifications.handleBackgroundMessage(message);
}

Future<void> _initializeOma() async {
  if (kIsWeb) {
    // Plain sqflite has no browser implementation — this swaps in the
    // IndexedDB-backed factory so the exact same LocalDatabase/SyncRepository
    // code (queries, transactions, the offline sync queue) works unmodified
    // on the web build too, instead of needing a separate web-only data layer.
    databaseFactory = databaseFactoryFfiWeb;
  }

  await LocalDatabase.instance.db;
  await OmaThemeController.initialize(LocalDatabase.instance);
  await OmaPushNotifications.requestInitialPermissions(LocalDatabase.instance);
  await OmaBackgroundSync.initialize();
  await OmaBackgroundSync.requestStartupSync();
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(
      omaFirebaseMessagingBackgroundHandler,
    );
  }
  runApp(
    const ProviderScope(
      child: OmaMobileAppRoot(),
    ),
  );
}

class OmaMobileAppRoot extends StatelessWidget {
  const OmaMobileAppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return OmaMobileApp(initialization: _initializeOma());
  }
}

class OmaMobileApp extends StatefulWidget {
  const OmaMobileApp({super.key, required this.initialization});

  final Future<void> initialization;

  @override State<OmaMobileApp> createState() => _OmaMobileAppState();
}

class _OmaMobileAppState extends State<OmaMobileApp> with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => OmaThemeController.refresh(
        systemBrightness:
            WidgetsBinding.instance.platformDispatcher.platformBrightness,
      ),
    );
  }

  @override
  void didChangePlatformBrightness() {
    OmaThemeController.refresh(
      systemBrightness:
          WidgetsBinding.instance.platformDispatcher.platformBrightness,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      OmaPushNotifications.clearPendingReminders();
      OmaThemeController.refresh(
        systemBrightness:
            WidgetsBinding.instance.platformDispatcher.platformBrightness,
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: OmaThemeController.resolvedMode,
      builder: (context, mode, _) => MaterialApp(
        title: 'Oma Mobile',
        debugShowCheckedModeBanner: false,
        themeMode: mode,
        theme: brandTheme(Brightness.light),
        darkTheme: brandTheme(Brightness.dark),
        home: FutureBuilder<void>(
          future: widget.initialization,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Scaffold(
                body: Center(child: BrandLoader()),
              );
            }

            if (snapshot.hasError) {
              return Scaffold(
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const BrandLoader(size: 72, label: null),
                        const SizedBox(height: 20),
                        const Text(
                          'Unable to start OmaSales.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          snapshot.error.toString(),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            return const SessionGate();
          },
        ),
      ),
    );
  }
}

// The Omabuy brand: the orange and green are sampled straight from the logo.
const brandOrange = Color(0xFFFC4300);
const brandGreen = Color(0xFF039664);

/// One theme for the whole app: white surfaces and green primary actions;
/// orange is reserved for attention/warning accents.
ThemeData brandTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;

  final scheme = ColorScheme.fromSeed(
    seedColor: brandGreen,
    brightness: brightness,
  ).copyWith(
    primary: brandGreen,
    onPrimary: Colors.white,
    secondary: brandOrange,
    onSecondary: Colors.white,
    tertiary: brandGreen,
    onTertiary: Colors.white,
    surface: dark ? const Color(0xFF111513) : Colors.white,
    surfaceContainer: dark ? const Color(0xFF18201C) : const Color(0xFFF7FAF8),
    surfaceContainerHighest:
        dark ? const Color(0xFF202A25) : const Color(0xFFEFF5F2),
    onSurface: dark ? Colors.white : const Color(0xFF18201C),
    outline: dark ? const Color(0xFF3A4841) : const Color(0xFFD6E2DC),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    cardTheme: CardTheme(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 8),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outline.withOpacity(.65)),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 20,
        fontWeight: FontWeight.w800,
      ),
      shape: Border(
        bottom: BorderSide(
          color: brandGreen.withOpacity(.55),
          width: 2,
        ),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: brandGreen.withOpacity(.16),
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withOpacity(.55),
      floatingLabelBehavior: FloatingLabelBehavior.always,
      labelStyle: TextStyle(
        color: scheme.onSurface.withOpacity(.78),
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      floatingLabelStyle: TextStyle(
        color: scheme.onSurface.withOpacity(.82),
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: brandGreen, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: brandGreen,
        foregroundColor: Colors.white,
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: brandGreen,
      foregroundColor: Colors.white,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: brandGreen,
    ),
  );
}

class SessionGate extends ConsumerStatefulWidget {
  const SessionGate({super.key});

  @override
  ConsumerState<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends ConsumerState<SessionGate> {
  late final ApiClient api;

  @override
  void initState() {
    super.initState();
    api = ref.read(apiClientProvider);
    BiometricGuard.passwordVerifier = (password) async {
      try {
        final result = await api.verifyPassword(password);
        return result['verified'] == true;
      } catch (_) {
        return false;
      }
    };
  }

  @override
  void dispose() {
    if (BiometricGuard.passwordVerifier != null) {
      BiometricGuard.passwordVerifier = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);

    return session.when(
      loading: () => const Scaffold(
        body: Center(child: BrandLoader()),
      ),
      error: (_, __) => LoginPage(api: api),
      data: (state) => state.authenticated
          ? _AuthenticatedShell(api: api)
          : LoginPage(api: api),
    );
  }
}

class _AuthenticatedShell extends StatefulWidget {
  const _AuthenticatedShell({required this.api});
  final ApiClient api;

  @override
  State<_AuthenticatedShell> createState() => _AuthenticatedShellState();
}

class _AuthenticatedShellState extends State<_AuthenticatedShell> {
  @override
  Widget build(BuildContext context) => AppShell(api: widget.api);
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
  bool biometricAvailable = false;
  String? savedBiometricUsername;

  @override
  void initState() {
    super.initState();
    _loadBiometricLogin();
  }

  Future<void> _loadBiometricLogin() async {
    final username = await widget.api.biometricUsername();
    final available = await BiometricGuard.canUseBiometrics();
    if (!mounted) return;
    setState(() {
      savedBiometricUsername = username;
      biometricAvailable = available;
      if (username != null && username.isNotEmpty) {
        this.username.text = username;
      }
    });

    // If this device already has a biometric credential for the account,
    // present the OS biometric prompt immediately when the login screen is
    // reached (including after the six-hour inactivity timeout).
    if (username != null &&
        username.isNotEmpty &&
        available &&
        mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !busy) biometricLogin();
      });
    }
  }

  Future<void> biometricLogin() async {
    final entered = username.text.trim();
    final savedUser = savedBiometricUsername;
    final credential = await widget.api.biometricCredential();

    if (!biometricAvailable ||
        entered.isEmpty ||
        savedUser == null ||
        credential == null ||
        entered.toLowerCase() != savedUser.toLowerCase()) {
      if (mounted) {
        setState(() => error =
            'Biometric sign-in is not available on this device. Use your password once.');
      }
      return;
    }

    final authenticated = await BiometricGuard.authenticateForLogin(
      reason: 'Use your fingerprint or device biometric to sign in to OmaSales.',
    );
    if (!authenticated) return;

    setState(() {
      busy = true;
      error = null;
    });

    try {
      final result = await widget.api.biometricLogin(
        entered,
        credential,
      );
      final token = result['token']?.toString();
      if (token == null || token.isEmpty) {
        throw Exception('Biometric login did not return a valid session.');
      }

      await widget.api.saveToken(token);
      final biometricCredential = result['biometric_credential']?.toString();
      if (biometricCredential != null && biometricCredential.isNotEmpty) {
        await widget.api.saveBiometricCredential(
          username.text.trim(),
          biometricCredential,
        );
      }
      await AppSession.refresh(widget.api);

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => AppShell(api: widget.api)),
        );
      }
    } catch (e) {
      await widget.api.clearBiometricCredential();
      if (mounted) {
        setState(() {
          savedBiometricUsername = null;
          error = 'Biometric login expired. Sign in with your password once to re-enable it.';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

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
      final biometricCredential = result['biometric_credential']?.toString();
      if (biometricCredential != null && biometricCredential.isNotEmpty) {
        await widget.api.saveBiometricCredential(
          username.text.trim(),
          biometricCredential,
        );
      }
      await AppSession.refresh(widget.api);

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => AppShell(api: widget.api),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = userFacingError(e));
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
                          onChanged: (_) => setState(() {}),
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
                        const SizedBox(height: 10),
                        if (biometricAvailable &&
                            savedBiometricUsername != null &&
                            username.text.trim().toLowerCase() ==
                                savedBiometricUsername!.toLowerCase())
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: busy ? null : biometricLogin,
                              icon: const Icon(Icons.fingerprint),
                              label: const Text('Use biometrics'),
                            ),
                          ),
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

class GlobalChatLauncher extends StatefulWidget {
  const GlobalChatLauncher({super.key, required this.api});
  final ApiClient api;

  @override
  State<GlobalChatLauncher> createState() => _GlobalChatLauncherState();
}

class _GlobalChatLauncherState extends State<GlobalChatLauncher>
    with SingleTickerProviderStateMixin {
  static const _lastReadKey = 'team_chat_last_read_id';

  bool open = false;
  int unreadCount = 0;
  int? _latestMessageId;
  bool _initialised = false;
  int? _pendingChatMessageId;
  Timer? _poller;
  late final AnimationController _pulseController;
  VoidCallback? _pushListener;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _poller = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _checkForUnreadMessages(),
    );
    _pushListener = () => _handlePushRequest(
          OmaPushNotifications.chatOpenRequest.value,
        );
    OmaPushNotifications.chatOpenRequest.addListener(_pushListener!);
    _checkForUnreadMessages();
    _handlePushRequest(OmaPushNotifications.chatOpenRequest.value);
    if (kIsWeb) {
      final messageId = Uri.base.queryParameters['chat_message_id'];
      if (messageId != null && messageId.isNotEmpty) {
        _pendingChatMessageId = int.tryParse(messageId);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !open) _openChat();
        });
      }
    }
  }

  void _handlePushRequest(Map<String, dynamic>? data) {
    if (!mounted || data == null || data['type'] != 'chat_message') return;
        final messageId = int.tryParse('${data['chat_message_id'] ?? ''}');
    _pendingChatMessageId = messageId;
    OmaPushNotifications.chatOpenRequest.value = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !open) _openChat();
    });
  }

  @override
  void dispose() {
    _poller?.cancel();
    if (_pushListener != null) {
      OmaPushNotifications.chatOpenRequest.removeListener(_pushListener!);
    }
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _checkForUnreadMessages() async {
    if (open) return;

    try {
      final rows = (await widget.api.chatMessages(limit: 100))
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();

      if (!mounted || rows.isEmpty) return;

      rows.sort(
        (a, b) => (int.tryParse('${a['id']}') ?? 0)
            .compareTo(int.tryParse('${b['id']}') ?? 0),
      );

      final latest = int.tryParse('${rows.last['id']}');
      if (latest == null) return;

      final stored = await LocalDatabase.instance.getMeta(_lastReadKey);
      final lastRead = int.tryParse(stored ?? '');

      if (!_initialised && lastRead == null) {
        await LocalDatabase.instance.setMeta(_lastReadKey, '$latest');
        if (!mounted) return;
        setState(() {
          _latestMessageId = latest;
          unreadCount = 0;
          _initialised = true;
        });
        return;
      }

      final effectiveLastRead = lastRead ?? 0;
      final unreadRows = rows.where((message) {
        final id = int.tryParse('${message['id']}') ?? 0;
        final senderId = int.tryParse('${message['sender_user_id']}');
        return id > effectiveLastRead && senderId != AppSession.userId;
      }).toList();

      final nextCount = unreadRows.length;
      final hadNewerMessage = _latestMessageId != null &&
          latest > _latestMessageId!;

      if (!mounted) return;
      setState(() {
        _latestMessageId = latest;
        unreadCount = nextCount;
        _initialised = true;
      });

      if ((hadNewerMessage || nextCount > 0) &&
          !_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      } else if (nextCount == 0) {
        _pulseController.stop();
        _pulseController.value = 0;
      }
    } catch (_) {}
  }

  Future<void> _markChatRead() async {
    try {
      final rows = (await widget.api.chatMessages(limit: 100))
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      if (rows.isEmpty) return;

      rows.sort(
        (a, b) => (int.tryParse('${a['id']}') ?? 0)
            .compareTo(int.tryParse('${b['id']}') ?? 0),
      );

      final latest = int.tryParse('${rows.last['id']}');
      if (latest == null) return;

      await LocalDatabase.instance.setMeta(_lastReadKey, '$latest');
      if (!mounted) return;
      setState(() {
        _latestMessageId = latest;
        unreadCount = 0;
      });
      _pulseController.stop();
      _pulseController.value = 0;
    } catch (_) {}
  }

  Future<void> _openChat() async {
    setState(() => open = true);
    await _markChatRead();

    final targetMessageId = _pendingChatMessageId;
    _pendingChatMessageId = null;

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close team chat',
      barrierColor: Colors.black.withOpacity(.35),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondaryAnimation) {
        final mobile = MediaQuery.sizeOf(context).width < 700;
        final chat = ChatPage(api: widget.api, initialMessageId: targetMessageId);
        if (mobile) {
          return Material(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: SafeArea(child: chat),
          );
        }
        return SafeArea(
          child: Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Material(
                color: Colors.transparent,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 560,
                    maxHeight: MediaQuery.sizeOf(context).height * .88,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: chat,
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: .94, end: 1).animate(curved),
            alignment: Alignment.bottomRight,
            child: child,
          ),
        );
      },
    );

    if (mounted) {
      setState(() => open = false);
      await _markChatRead();
      _checkForUnreadMessages();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Positioned(
      right: 18,
      bottom: 94,
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          final pulse = _pulseController.value;
          return Transform.scale(
            scale: unreadCount > 0 ? 1 + pulse * .055 : 1,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                boxShadow: unreadCount > 0
                    ? [
                        BoxShadow(
                          color: scheme.primary.withOpacity(.28 + pulse * .30),
                          blurRadius: 12 + pulse * 14,
                          spreadRadius: 2 + pulse * 3,
                        ),
                      ]
                    : const [],
              ),
              child: child,
            ),
          );
        },
        child: FloatingActionButton.extended(
          heroTag: 'global-team-chat',
          onPressed: open ? null : _openChat,
          backgroundColor:
              unreadCount > 0 ? scheme.primary : scheme.primaryContainer,
          foregroundColor:
              unreadCount > 0 ? scheme.onPrimary : scheme.onPrimaryContainer,
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.forum_rounded),
              if (unreadCount > 0)
                Positioned(
                  right: -10,
                  top: -11,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 22),
                    height: 22,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: scheme.secondary,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: unreadCount > 0
                            ? scheme.primary
                            : scheme.surface,
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: scheme.secondary.withOpacity(.35),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: Text(
                      unreadCount > 99 ? '99+' : '$unreadCount',
                      style: TextStyle(
                        color: scheme.onSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          label: Text(
            unreadCount > 0
                ? '${unreadCount == 1 ? 'New chat' : 'New chats'}'
                : 'Team chat',
          ),
        ),
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.api});

  final ApiClient api;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  final local = LocalDatabase.instance;

  late final repo = SyncRepository(
    widget.api,
    local,
  );

  StreamSubscription<List<ConnectivityResult>>? connectivity;

  // Home is the center destination in the shared app/web navigation.
  int tab = 2;
  bool syncing = false;
  String syncText = 'Ready';
  int refreshKey = 0;
  Timer? inactivityTimer;
  DateTime _lastActivity = DateTime.now();

  @override
  void initState() {
    super.initState();

    // LoginPage enters AppShell directly, so the SessionGate verifier must
    // also be installed here for biometric-protected settings and actions.
    BiometricGuard.passwordVerifier = (password) async {
      try {
        final result = await widget.api.verifyPassword(password);
        return result['verified'] == true;
      } catch (_) {
        return false;
      }
    };

    // Register push notifications on every authenticated entry path,
    // including a fresh login that bypasses _AuthenticatedShell.
    OmaPushNotifications.initialize(widget.api);

    _lastActivity = DateTime.now();
    inactivityTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _checkInactivity(),
    );

    _validateServerSession();
    AppSession.refresh(widget.api);

    connectivity = Connectivity()
        .onConnectivityChanged
        .listen((results) {
          if (results.any((result) => result != ConnectivityResult.none)) {
            sync(silent: true);
          }
        });

    sync(silent: true);
  }

  Future<void> _validateServerSession() async {
    try {
      await widget.api.me();
    } on ApiException catch (e) {
      if (e.statusCode != 401 || !mounted) return;
      await widget.api.clearToken();
      AppSession.reset();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => LoginPage(api: widget.api)),
        (_) => false,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your session expired. Sign in again or use biometrics.'),
        ),
      );
    } catch (_) {
      // A temporary network failure is not a logout.
    }
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
        showNetworkError(
          context,
          e,
          onRetry: () => sync(silent: false),
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

  void _touchActivity() {
    _lastActivity = DateTime.now();
  }

  Future<void> _checkInactivity() async {
    if (DateTime.now().difference(_lastActivity) < const Duration(hours: 6)) {
      return;
    }

    await widget.api.clearToken();
    AppSession.reset();

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LoginPage(api: widget.api)),
      (_) => false,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('You were logged out after 6 hours of inactivity.')),
    );
  }

  Future<void> logout() async {
    await widget.api.clearToken();
    // Keep the device biometric credential across an explicit sign-out so
    // this previously trusted device can use its OS biometric to sign in
    // again. The server-side credential is invalidated when the password changes.
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
    inactivityTimer?.cancel();
    if (BiometricGuard.passwordVerifier != null) {
      BiometricGuard.passwordVerifier = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Same destination order on Android, iOS and Flutter Web.
    // Home is deliberately the physical center item.
    final pages = [
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
      DashboardPage(
        api: widget.api,
        local: local,
        repo: repo,
        syncText: syncText,
        syncing: syncing,
        onSync: sync,
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

    final content = Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _touchActivity(),
      onPointerMove: (_) => _touchActivity(),
      onPointerSignal: (_) => _touchActivity(),
      child: IndexedStack(
        index: tab,
        children: pages,
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1100;

        Widget workspace() {
          return Stack(
            children: [
              Positioned.fill(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1480),
                    child: content,
                  ),
                ),
              ),
              GlobalChatLauncher(api: widget.api),
            ],
          );
        }

        if (wide) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: tab,
                  onDestinationSelected: (i) => setState(() => tab = i),
                  labelType: NavigationRailLabelType.all,
                  leading: Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 18),
                    child: InkWell(
                      onTap: () => setState(() => tab = 2),
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Image.asset('assets/images/app_icon.png', width: 38, height: 38),
                      ),
                    ),
                  ),
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.receipt_long_outlined),
                      selectedIcon: Icon(Icons.receipt_long),
                      label: Text('Sales'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.inventory_2_outlined),
                      selectedIcon: Icon(Icons.inventory_2),
                      label: Text('Products'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.dashboard_outlined),
                      selectedIcon: Icon(Icons.dashboard),
                      label: Text('Home'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.warehouse_outlined),
                      selectedIcon: Icon(Icons.warehouse),
                      label: Text('Stock'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.more_horiz),
                      selectedIcon: Icon(Icons.more_horiz),
                      label: Text('More'),
                    ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: workspace()),
              ],
            ),
          );
        }

        return Scaffold(
          body: workspace(),
          bottomNavigationBar: _OmaBottomNavigation(
            selectedIndex: tab,
            onSelected: (i) => setState(() => tab = i),
          ),
        );
      },
    );

  }
}

class _OmaBottomNavigation extends StatelessWidget {
  const _OmaBottomNavigation({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const _items = <(IconData, IconData, String)>[
    (Icons.receipt_long_outlined, Icons.receipt_long, 'Sales'),
    (Icons.inventory_2_outlined, Icons.inventory_2, 'Products'),
    (Icons.dashboard_outlined, Icons.dashboard, 'Home'),
    (Icons.warehouse_outlined, Icons.warehouse, 'Stock'),
    (Icons.more_horiz, Icons.more_horiz, 'More'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Material(
        color: scheme.surface,
        elevation: 14,
        child: Container(
          height: 82,
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: scheme.outline.withOpacity(.55)),
            ),
          ),
          child: Row(
            children: List.generate(_items.length, (index) {
              final item = _items[index];
              final selected = selectedIndex == index;
              if (index == 2) {
                return Expanded(
                  child: InkWell(
                    onTap: () => onSelected(index),
                    child: Transform.translate(
                      offset: const Offset(0, -14),
                      child: Center(
                        child: Container(
                          width: 68,
                          height: 68,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                brandGreen,
                                scheme.primary,
                                brandGreen.withOpacity(.72),
                              ],
                            ),
                            border: Border.all(
                              color: Colors.white.withOpacity(.82),
                              width: 3,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: brandGreen.withOpacity(.35),
                                blurRadius: 18,
                                spreadRadius: 2,
                                offset: const Offset(0, 7),
                              ),
                            ],
                          ),
                          child: Image.asset(
                            'assets/images/app_icon.png',
                            width: 40,
                            height: 40,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }
              return Expanded(
                child: InkWell(
                  onTap: () => onSelected(index),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 5),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          selected ? item.$2 : item.$1,
                          color: selected
                              ? scheme.primary
                              : scheme.onSurface.withOpacity(.58),
                          size: 23,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.$3,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight:
                                selected ? FontWeight.w800 : FontWeight.w600,
                            color: selected
                                ? scheme.primary
                                : scheme.onSurface.withOpacity(.62),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class DashboardPage extends ConsumerStatefulWidget {
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
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) load();
    });
  }

  @override
  void didUpdateWidget(covariant DashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.refreshKey != widget.refreshKey) {
      load();
    }
  }

  Future<void> load() async {
    await ref.read(dashboardControllerProvider.notifier).refresh();
  }
  @override
  Widget build(BuildContext context) {
    final dashboard = ref.watch(dashboardControllerProvider);
    final data = dashboard.valueOrNull?.data ?? <String, dynamic>{};
    final pending =
        dashboard.valueOrNull?.pendingOperations ?? 0;

    return RefreshIndicator(
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
                    // Primary actions stay above the dashboard data.
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final compact = constraints.maxWidth < 520;
                            final children = [
                              FilledButton.icon(
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => NewSalePage(
                                    ),
                                  ),
                                ),
                                icon: const Icon(Icons.add_shopping_cart),
                                label: const Text('Preorder sale'),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => NewSalePage(
                                      stocked: true,
                                    ),
                                  ),
                                ),
                                icon: const Icon(Icons.inventory_2_outlined),
                                label: const Text('Stock sale'),
                              ),
                              OutlinedButton.icon(
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
                            ];
                            if (compact) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (var i = 0; i < children.length; i++) ...[
                                    children[i],
                                    if (i < children.length - 1)
                                      const SizedBox(height: 8),
                                  ],
                                ],
                              );
                            }
                            return Row(
                              children: [
                                for (var i = 0; i < children.length; i++) ...[
                                  Expanded(child: children[i]),
                                  if (i < children.length - 1)
                                    const SizedBox(width: 8),
                                ],
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
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
                    if (dashboard.hasValue)
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
                                '₦${_money(data['sales_today'])}',
                            icon: Icons.payments,
                          ),
                          _Kpi(
                            title: 'Profit today',
                            value:
                                '₦${_money(data['profit_today'])}',
                            icon: Icons.trending_up,
                          ),
                          _Kpi(
                            title: 'Pending shipments',
                            value:
                                '${data['pending_shipments'] ?? 0}',
                            icon: Icons.local_shipping,
                          ),
                          _Kpi(
                            title: 'Low stock',
                            value:
                                '${data['low_stock_count'] ?? 0}',
                            icon: Icons.warning_amber,
                          ),
                          _Kpi(
                            title: 'Shipping owed',
                            value:
                                '₦${data['shipping_owed'] ?? 0}',
                            icon: Icons.account_balance_wallet_outlined,
                          ),
                          _Kpi(
                            title: 'Batches in transit',
                            value:
                                '${data['batches_in_transit'] ?? 0}',
                            icon: Icons.flight_takeoff,
                          ),
                          _Kpi(
                            title: 'Sync exceptions',
                            value:
                                '${data['sync_exceptions'] ?? 0}',
                            icon: Icons.sync_problem,
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
                    if ((data['low_stock_products'] as List?)
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
                                data['low_stock_products'],
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
                  ],
                ),
              ),
            ),
          ],
        ),
      );
  }
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

  late final supplierCost = TextEditingController(
    text: widget.product?['supplier_cost']?.toString() ??
            widget.product?['cost']?.toString() ?? '',
  );

  late final landedCost = TextEditingController(
    text: widget.product?['cost']?.toString() ?? '',
  );

  late final markup = TextEditingController(
    text: widget.product?['markup_percent']?.toString() ?? '0',
  );

  late final sellingPrice = TextEditingController(
    text: widget.product?['selling_price']?.toString() ?? '',
  );

  late final shippingCost = TextEditingController(
    text: widget.product?['inbound_shipping_cost']?.toString() ?? '0',
  );

  String shippingMode = 'sea';
  bool calculating = false;
  Map<String, dynamic>? costResult;

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
      supplierCost,
      landedCost,
      markup,
      sellingPrice,
      shippingCost,
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

    if (landedCost.text.trim().isEmpty) {
      setState(() => error = 'Calculate the true landed cost before saving.');
      return;
    }

    setState(() => busy = true);

    try {
      if (widget.product == null) {
        await widget.repo.createProductOnline(
          name: name.text,
          sku: sku.text,
          cost: landedCost.text,
          supplierCost: supplierCost.text,
          inboundShippingCost: shippingCost.text,
          markupPercent: markup.text,
          sellingPrice: sellingPrice.text,
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
            'cost': landedCost.text,
            'supplier_cost': supplierCost.text,
            'inbound_shipping_cost': shippingCost.text,
            'markup_percent': markup.text,
            'selling_price': sellingPrice.text,
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
        setState(() => error = userFacingError(e));
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> calculateTrueCost() async {
    setState(() {
      calculating = true;
      error = null;
    });
    try {
      final result = await widget.api.calculateProductCost(
        cost: supplierCost.text,
        lengthCm: l.text,
        widthCm: w.text,
        heightCm: h.text,
        actualWeightKg: weight.text,
        markupPercent: markup.text,
        mode: shippingMode,
      );
      landedCost.text = (result['landed_cost'] ?? 0).toString();
      shippingCost.text = (result['shipping_cost'] ?? 0).toString();
      sellingPrice.text = (result['selling_price'] ?? 0).toString();
      costResult = result;
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => error = 'Could not calculate cost: $e');
    } finally {
      if (mounted) setState(() => calculating = false);
    }
  }

  Widget _financeRow(String label, dynamic value, {bool bold = false}) {
    final display = value is num ? value.toStringAsFixed(2) : '$value';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 12),
          Text(display, style: TextStyle(fontWeight: bold ? FontWeight.w900 : FontWeight.w600)),
        ],
      ),
    );
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
                const SizedBox(height: 14),
                TextField(
                  controller: sku,
                  decoration:
                      const InputDecoration(labelText: 'SKU'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: supplierCost,
                  keyboardType:
                      const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Supplier cost',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: markup,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Markup %',
                    helperText: 'Example: 30 means 30% above true cost',
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: shippingMode,
                  decoration: const InputDecoration(labelText: 'Inbound shipping mode'),
                  items: const [
                    DropdownMenuItem(value: 'sea', child: Text('Sea')),
                    DropdownMenuItem(value: 'air', child: Text('Air')),
                  ],
                  onChanged: calculating ? null : (v) {
                    if (v != null) setState(() => shippingMode = v);
                  },
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: calculating ? null : calculateTrueCost,
                  icon: calculating
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.calculate_rounded),
                  label: Text(calculating ? 'Calculating…' : 'Calculate true cost'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: landedCost,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'True landed cost / unit',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: shippingCost,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Inbound shipping / unit',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: sellingPrice,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Suggested selling price / unit',
                  ),
                ),
                const SizedBox(height: 14),
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
                const SizedBox(height: 14),
                TextField(
                  controller: weight,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Actual weight kg',
                  ),
                ),
                if (costResult != null) ...[
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Financial breakdown', style: TextStyle(fontWeight: FontWeight.w900)),
                          const SizedBox(height: 10),
                          _financeRow('Product / supplier cost', costResult!['supplier_cost']),
                          _financeRow('Volume shipping', costResult!['volume_shipping_cost']),
                          _financeRow('Weight + packaging', costResult!['weight_shipping_cost']),
                          const Divider(),
                          _financeRow('True landed cost', costResult!['landed_cost'], bold: true),
                          _financeRow('Break-even price', costResult!['break_even_price'], bold: true),
                          _financeRow('Markup', '${costResult!['markup_percent'] ?? 0}%'),
                          _financeRow('Selling price', costResult!['selling_price'], bold: true),
                          _financeRow('Gross profit / unit', costResult!['gross_profit'], bold: true),
                          _financeRow('Gross margin', '${(costResult!['gross_margin_percent'] ?? 0).toStringAsFixed(2)}%', bold: true),
                          _financeRow('Shipping mode', '${costResult!['mode']}'.toUpperCase()),
                          _financeRow('Volume rate', costResult!['volume_rate']),
                          _financeRow('Packing rate / kg', costResult!['packing_rate_per_kg']),
                        ],
                      ),
                    ),
                  ),
                ],
                if (widget.product == null) const SizedBox(height: 14),
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
          SnackBar(content: Text(userFacingError(e))),
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
          SnackBar(content: Text(userFacingError(e))),
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
        body: Center(child: BrandLoader()),
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
                child: const Text('Try Again'),
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
            const SizedBox(height: 12),
            JourneyCard(
              api: widget.api,
              saleId: widget.saleId,
            ),
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
            const SizedBox(height: 14),
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
            const SizedBox(height: 14),
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
            content: Text(userFacingError(e)),
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
                leading: const Icon(Icons.palette_outlined),
                title: const Text('Appearance'),
                subtitle: const Text(
                  'System, sunset to sunrise, light or dark',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ThemeSettingsPage(),
                  ),
                ),
              ),
            ),
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
                      repo: repo,
                      refreshKey: refreshKey,
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
                leading: const Icon(Icons.account_circle_outlined),
                title: const Text('My profile'),
                subtitle: const Text('Username, profile photo and password'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProfilePage(api: api),
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
            if (!kIsWeb)
            Card(
              child: ListTile(
                leading: const Icon(Icons.notifications_active_outlined),
                title: const Text('Test push notifications'),
                subtitle: const Text(
                  'Send a test notification to this device',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    final result = await api.testPushNotification();
                    final sent = result['sent'] ?? 0;
                    final errors = (result['errors'] as List?)
                            ?.map((x) => '$x')
                            .where((x) => x.isNotEmpty)
                            .toList() ??
                        const <String>[];
                    if (sent > 0) {
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Push test sent. Check this device for the notification.',
                          ),
                        ),
                      );
                    } else {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            errors.isNotEmpty
                                ? errors.first
                                : 'Push test was not delivered.',
                          ),
                        ),
                      );
                    }
                  } catch (e) {
                    messenger.showSnackBar(
                      SnackBar(content: Text('Push test failed: ${userFacingError(e)}')),
                    );
                  }
                },
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
  bool obscureCurrent = true;
  bool obscureNext = true;
  bool obscureConfirm = true;
  String? error;

  Future<void> save() async {
    if (next.text.length < 8 ||
        next.text != confirm.text) {
      setState(
        () => error =
            'New passwords must match and be at least 8 characters.',
      );
      return;
    }

    setState(() => busy = true);

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
        setState(() => error = userFacingError(e));
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
              obscureText: obscureCurrent,
              decoration: InputDecoration(
                labelText: 'Current password',
                suffixIcon: IconButton(
                  onPressed: () => setState(() => obscureCurrent = !obscureCurrent),
                  icon: Icon(obscureCurrent ? Icons.visibility : Icons.visibility_off),
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: next,
              obscureText: obscureNext,
              decoration: InputDecoration(
                labelText: 'New password',
                suffixIcon: IconButton(
                  onPressed: () => setState(() => obscureNext = !obscureNext),
                  icon: Icon(obscureNext ? Icons.visibility : Icons.visibility_off),
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: confirm,
              obscureText: obscureConfirm,
              decoration: InputDecoration(
                labelText: 'Confirm new password',
                suffixIcon: IconButton(
                  onPressed: () => setState(() => obscureConfirm = !obscureConfirm),
                  icon: Icon(obscureConfirm ? Icons.visibility : Icons.visibility_off),
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

  Future<void> discardFailedSale(Map<String, dynamic> row) async {
    final localSaleId = row['local_sale_id'] as int?;
    final operationId = row['operation_id']?.toString();
    if (localSaleId == null || operationId == null || operationId.isEmpty) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard failed sale?'),
        content: const Text(
          'This removes the unsynced sale from this device. If it was a stocked sale, the locally reserved stock will be restored. The server was not able to accept this sale.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await widget.local.removeLocalSaleAndRestoreStock(localSaleId);
    await widget.local.deleteSyncOperation(operationId);

    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Failed sale discarded and local stock restored where applicable.',
          ),
        ),
      );
    }
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
                    trailing: status == 'failed' &&
                            x['operation_type'] == 'create_sale' &&
                            x['local_sale_id'] != null
                        ? IconButton(
                            tooltip: 'Discard failed sale',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => discardFailedSale(x),
                          )
                        : null,
                  ),
                );
              },
            );
          },
        ),
      );
}
