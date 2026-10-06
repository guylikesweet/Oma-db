import '../../domain/entities/session_state.dart';
import '../../domain/repositories/session_repository.dart';
import '../api_client.dart';
import '../app_session.dart';

class SessionRepositoryImpl implements SessionRepository {
  const SessionRepositoryImpl(this.api);

  final ApiClient api;

  @override
  Future<SessionState> restore() async {
    final token = await api.token();
    if (token == null || token.isEmpty) {
      AppSession.reset();
      return const SessionState.signedOut();
    }

    try {
      return await refresh();
    } catch (_) {
      // Preserve the existing cached role during transient outages.
      return SessionState(
        userId: AppSession.userId,
        username: AppSession.username,
        role: AppSession.role,
        isPrimaryAdmin: AppSession.isPrimaryAdmin,
        authenticated: true,
      );
    }
  }

  @override
  Future<SessionState> refresh() async {
    await AppSession.refresh(api);
    return SessionState(
      userId: AppSession.userId,
      username: AppSession.username,
      role: AppSession.role,
      isPrimaryAdmin: AppSession.isPrimaryAdmin,
      authenticated: AppSession.userId != null,
    );
  }

  @override
  Future<void> reset() async {
    AppSession.reset();
    await api.clearToken();
  }
}
