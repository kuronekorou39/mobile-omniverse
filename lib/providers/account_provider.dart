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
      String accountId, Object newCredentials) async {
    final account = _storage.getAccount(accountId);
    if (account == null) return;
    final updated = account.copyWith(credentials: newCredentials);
    await _storage.updateAccount(updated);
    state = _storage.accounts;
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
