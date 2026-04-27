import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/draft_service.dart';

class DraftListNotifier extends StateNotifier<AsyncValue<List<Draft>>> {
  DraftListNotifier() : super(const AsyncValue.loading()) {
    reload();
  }

  Future<void> reload() async {
    final list = await DraftService.instance.loadAll();
    if (mounted) state = AsyncValue.data(list);
  }

  Future<void> upsert(Draft draft) async {
    await DraftService.instance.upsert(draft);
    await reload();
  }

  Future<void> delete(String id) async {
    await DraftService.instance.delete(id);
    await reload();
  }
}

final draftListProvider =
    StateNotifierProvider<DraftListNotifier, AsyncValue<List<Draft>>>(
  (ref) => DraftListNotifier(),
);
