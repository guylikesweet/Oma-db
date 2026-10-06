import '../entities/session_state.dart';

abstract interface class SessionRepository {
  Future<SessionState> restore();
  Future<SessionState> refresh();
  Future<void> reset();
}
