import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';

final productsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, bool>((ref, stockedOnly) {
  return ref.watch(productRepositoryProvider).list(
        stockedOnly: stockedOnly,
      );
});
