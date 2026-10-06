import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/session_state.dart';
import '../providers/app_providers.dart';

final sessionControllerProvider =
    AsyncNotifierProvider<SessionController, SessionState>(
  SessionController.new,
);

class SessionController extends AsyncNotifier<SessionState> {
  @override
  Future<SessionState> build() {
    return ref.read(sessionRepositoryProvider).restore();
  }

  Future<void> refreshSession() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(sessionRepositoryProvider).refresh(),
    );
  }

  Future<void> signOut() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () async {
        await ref.read(sessionRepositoryProvider).reset();
        return const SessionState.signedOut();
      },
    );
  }
}
