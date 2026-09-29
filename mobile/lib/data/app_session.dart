import 'api_client.dart';

/// In-memory cache of the signed-in user's role, so screens can check
/// `AppSession.isAdmin` synchronously instead of awaiting /v1/auth/me on
/// every build. Call [refresh] on login and whenever a screen that gates on
/// role is opened, so a role change (or a fresh login) is picked up quickly.
class AppSession {
  AppSession._();

  static int? userId;
  static String username = '';
  static String role = 'staff';
  static bool isPrimaryAdmin = false;

  static bool get isAdmin => role == 'admin';

  static Future<void> refresh(ApiClient api) async {
    try {
      final me = await api.me();
      userId = int.tryParse('${me['id'] ?? ''}');
      username = '${me['username'] ?? ''}';
      role = '${me['role'] ?? 'staff'}';
      isPrimaryAdmin = me['is_primary_admin'] == true;
    } catch (_) {
      // Transient network error — keep whatever we already had rather than
      // yanking admin screens away mid-session.
    }
  }

  static void reset() {
    userId = null;
    username = '';
    role = 'staff';
    isPrimaryAdmin = false;
  }
}
