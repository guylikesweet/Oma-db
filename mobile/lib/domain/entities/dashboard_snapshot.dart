class DashboardSnapshot {
  const DashboardSnapshot({
    required this.data,
    required this.pendingOperations,
    required this.fromLocalData,
  });

  final Map<String, dynamic> data;
  final int pendingOperations;
  final bool fromLocalData;
}
