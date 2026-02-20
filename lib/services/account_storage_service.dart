import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/account.dart';

class AccountStorageService {
  AccountStorageService._();
  static final instance = AccountStorageService._();

  static const _key = 'accounts';
  static const _secureStorage = FlutterSecureStorage();

  List<Account> _accounts = [];
  List<Account> get accounts => List.unmodifiable(_accounts);

  Future<void> load() async {
    // Try secure storage first
    String? raw;
    try {
      raw = await _secureStorage.read(key: _key);
    } catch (e) {
      debugPrint('[AccountStorage] Secure storage read failed: $e');
    }

    // Fallback: migrate from SharedPreferences if secure storage is empty
    if (raw == null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        raw = prefs.getString(_key);
        if (raw != null) {
          // Migrate to secure storage
          await _secureStorage.write(key: _key, value: raw);
          await prefs.remove(_key);
          debugPrint('[AccountStorage] Migrated from SharedPreferences to secure storage');
        }
      } catch (e) {
        debugPrint('[AccountStorage] SharedPreferences migration failed: $e');
      }
    }

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
    final data = _accounts.map((a) => a.toJson()).toList();
    final encoded = json.encode(data);
    try {
      await _secureStorage.write(key: _key, value: encoded);
    } catch (e) {
      debugPrint('[AccountStorage] Secure storage write failed: $e');
      // Fallback to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, encoded);
    }
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
