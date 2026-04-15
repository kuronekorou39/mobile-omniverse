import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/account.dart';
import '../models/sns_service.dart';
import '../services/account_storage_service.dart';

class AccountNotifier extends StateNotifier<List<Account>> {
  AccountNotifier() : super([]) {
    _load();
  }

  final _storage = AccountStorageService.instance;

  Future<void> _load() async {
    state = _storage.accounts;
  }

  Future<void> addAccount(Account account) async {
    await _storage.addAccount(account);
    state = _storage.accounts;
  }

  Future<void> removeAccount(String accountId) async {
    await _storage.removeAccount(accountId);
    state = _storage.accounts;
  }

  Future<void> toggleAccount(String accountId) async {
    final account = _storage.getAccount(accountId);
    if (account == null) return;
    final updated = account.copyWith(isEnabled: !account.isEnabled);
    await _storage.updateAccount(updated);
    state = _storage.accounts;
  }

  Future<void> updateCredentials(
      String accountId, SnsCredentials newCredentials) async {
    final account = _storage.getAccount(accountId);
    if (account == null) return;
    final updated = account.copyWith(credentials: newCredentials);
    await _storage.updateAccount(updated);
    state = _storage.accounts;
  }

  Future<void> updateProtectedStatus(String accountId, bool isProtected) async {
    final account = _storage.getAccount(accountId);
    if (account == null || account.isProtected == isProtected) return;
    await _storage.updateAccount(account.copyWith(isProtected: isProtected));
    state = _storage.accounts;
  }

  Future<void> enableAll() async {
    for (final account in _storage.accounts) {
      if (!account.isEnabled) {
        await _storage.updateAccount(account.copyWith(isEnabled: true));
      }
    }
    state = _storage.accounts;
  }

  Future<void> disableAll() async {
    for (final account in _storage.accounts) {
      if (account.isEnabled) {
        await _storage.updateAccount(account.copyWith(isEnabled: false));
      }
    }
    state = _storage.accounts;
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    // 先にUIを更新してチラつきを防止、ストレージ保存は非同期で後追い
    final accounts = List<Account>.of(state);
    final adjustedNew = newIndex > oldIndex ? newIndex - 1 : newIndex;
    final item = accounts.removeAt(oldIndex);
    accounts.insert(adjustedNew, item);
    state = accounts;
    // _storage.reorderは内部でnewIndex調整するので元の値を渡す
    _storage.reorder(oldIndex, newIndex);
  }

  List<Account> accountsForService(SnsService service) {
    return state.where((a) => a.service == service).toList();
  }

  Future<void> reload() async {
    await _storage.load();
    state = _storage.accounts;
  }
}

final accountProvider =
    StateNotifierProvider<AccountNotifier, List<Account>>(
  (ref) => AccountNotifier(),
);
