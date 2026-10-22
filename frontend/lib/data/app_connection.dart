import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../app.dart';
import '../state/expense_store.dart';
import '../screens/login_screen.dart';
import '../screens/password_recovery_screen.dart';
import '../screens/home_shell.dart';
import 'backend_api.dart';
import '../services/auth/session_access.dart';
import '../services/auth/profile_name.dart';
import '../state/account_scope.dart';

class AppConnection extends StatefulWidget {
  const AppConnection({
    super.key,
    required this.baseUrl,
    this.auth,
    this.apiFactory,
  });
  final String baseUrl;
  final GoTrueClient? auth;
  final BackendApi Function(String baseUrl, Future<String> Function() token)?
  apiFactory;
  @override
  State<AppConnection> createState() => _AppConnectionState();
}

class _AppConnectionState extends State<AppConnection> {
  late final _auth = widget.auth ?? Supabase.instance.client.auth;
  StreamSubscription<AuthState>? _subscription;
  ExpenseStore? _store;
  String? _userId;
  String? _authError;
  bool _recovering = false;
  bool _restoring = false;
  @override
  void initState() {
    super.initState();
    _acceptSession(_auth.currentSession);
    _subscription = _auth.onAuthStateChange.listen(
      (event) {
        if (mounted) {
          setState(() {
            _authError = null;
            if (event.event == AuthChangeEvent.passwordRecovery) {
              _recovering = true;
            }
            if (event.session == null) _recovering = false;
            _acceptSession(event.session);
          });
        }
      },
      onError: (Object error, StackTrace stack) {
        if (mounted) {
          setState(
            () => _authError =
                'Your session or recovery link could not be verified. Check your connection or request a new link.',
          );
        }
      },
    );
  }

  // Une session expirée restaurée du disque ne suffit pas pour afficher Home.
  // Supabase effectue le refresh et reste l’unique source de vérité.
  void _acceptSession(Session? session) {
    if (session != null && session.isExpired) {
      final alreadyRestoring = _restoring;
      _restoring = true;
      _session(null);
      if (!alreadyRestoring) unawaited(_restoreSession(session));
      return;
    }
    _restoring = false;
    _session(session);
  }

  Future<void> _restoreSession(Session expired) async {
    try {
      await _auth.refreshSession();
      if (mounted) setState(() => _acceptSession(_auth.currentSession));
    } catch (_) {
      // Un échec ancien ne doit pas effacer un compte connecté entre-temps.
      final current = _auth.currentSession;
      if (current != null && current.accessToken != expired.accessToken) return;
      if (mounted) {
        setState(() {
          _restoring = false;
          _session(null);
          _authError =
              'Your session could not be restored. Please sign in again.';
        });
      }
    }
  }

  void _session(Session? session) {
    if (_userId == session?.user.id) return;
    final previous = _store;
    previous?.invalidateSession();
    _userId = session?.user.id;
    if (session == null) {
      _store = null;
    } else {
      final owner = session.user.id;
      final token = SessionAccess(_auth, owner).token;
      _store = ExpenseStore(
        api:
            widget.apiFactory?.call(widget.baseUrl, token) ??
            BackendApi(baseUrl: widget.baseUrl, accessToken: token),
      );
    }
    // Let the previous widget tree unmount before disposing its notifier.
    if (previous != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _store?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AccountScope(
    email: _auth.currentUser?.email,
    firstName: profileFirstName(
      _auth.currentUser?.userMetadata,
      _auth.currentUser?.email,
    ),
    signOut: () => _auth.signOut(),
    child: SnapExpenseApp(
      key: ValueKey('$_userId-$_recovering-$_restoring'),
      store: _store,
      destination: _restoring
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _recovering && _store != null
          ? const NewPasswordScreen()
          : _store == null
          ? LoginScreen(message: _authError)
          : SyncDashboard(store: _store!, authError: _authError),
    ),
  );
}

class SyncDashboard extends StatefulWidget {
  const SyncDashboard({super.key, required this.store, this.authError});
  final ExpenseStore store;
  final String? authError;
  @override
  State<SyncDashboard> createState() => _SyncDashboardState();
}

class _SyncDashboardState extends State<SyncDashboard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.store.refresh();
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (widget.authError != null)
        Material(
          color: const Color(0xFFFFE9D8),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(widget.authError!),
            ),
          ),
        ),
      const Expanded(child: HomeShell()),
    ],
  );
}

class ConnectionSetupScreen extends StatelessWidget {
  const ConnectionSetupScreen({super.key, this.message});
  final String? message;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.settings_ethernet_rounded,
                  size: 48,
                  color: Color(0xFF42634B),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Connect SnapExpense',
                  style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                Text(
                  message ??
                      'Set API_BASE_URL, SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY in config/local.json, then run with --dart-define-from-file=config/local.json.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
