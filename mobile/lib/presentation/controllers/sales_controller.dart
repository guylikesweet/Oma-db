import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/usecases/create_sale.dart';
import '../providers/app_providers.dart';

final saleSavingProvider =
    StateProvider.autoDispose<bool>((ref) => false);

final saleMessageProvider =
    StateProvider.autoDispose<String?>((ref) => null);

final createSaleControllerProvider =
    Provider<CreateSale>((ref) => ref.watch(createSaleProvider));
