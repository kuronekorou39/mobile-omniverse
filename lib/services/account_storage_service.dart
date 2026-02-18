import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/account.dart';

class AccountStorageService {
  AccountStorageService._();
  static final instance = AccountStorageService._();

  static const _key = 'accounts';

  List<Account> _accounts = [];
  List<Account> get accounts => List.unmodifiable(_accounts);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) {
      _accounts = [];
      return;
    }

    final List<dynamic> list = json.decode(raw);
    _accounts = list
        .map((e) => Account.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _accounts.map((a) => a.toJson()).toList();
    await prefs.setString(_key, json.encode(data));
  }

  Future<void> addAccount(Account account) async {
    _accounts.add(account);
    await _save();
  }

  Future<void> removeAccount(String accountId) async {
    _accounts.removeWhere((a) => a.id == accountId);
    await _save();
  }

  Future<void> updateAccount(Account account) async {
    final index = _accounts.indexWhere((a) => a.id == account.id);
    if (index >= 0) {
      _accounts[index] = account;
      await _save();
    }
  }

  Account? getAccount(String accountId) {
    try {
      return _accounts.firstWhere((a) => a.id == accountId);
    } catch (_) {
      return null;
    }
  }
}
