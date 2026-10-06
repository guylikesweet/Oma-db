import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/dashboard_snapshot.dart';
import '../providers/app_providers.dart';

final dashboardControllerProvider =
    AsyncNotifierProvider<DashboardController, DashboardSnapshot>(
  DashboardController.new,
);

class DashboardController extends AsyncNotifier<DashboardSnapshot> {
  @override
  Future<DashboardSnapshot> build() {
    return ref.read(dashboardRepositoryProvider).load();
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(
      () => ref.read(dashboardRepositoryProvider).load(),
    );
  }
}
