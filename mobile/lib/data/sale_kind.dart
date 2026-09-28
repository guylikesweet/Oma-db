/// Stocked-goods sales use the OMBSTK- prefix (OFFSTK- while still offline
/// and unsynced). Preorder sales use OMB- / OFF-.
bool isStockSale(Map<dynamic, dynamic> sale) {
  if (sale['sale_type'] == 'stock') return true;
  final id = '${sale['order_id'] ?? ''}';
  return id.startsWith('OMBSTK-') || id.startsWith('OFFSTK-');
}
