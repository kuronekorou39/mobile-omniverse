import 'dart:convert';

import 'sns_service.dart';

/// Bluesky (AT Protocol) の認証情報
class BlueskyCredentials {
  const BlueskyCredentials({
    required this.accessJwt,
    required this.refreshJwt,
    required this.did,
    required this.handle,
    this.pdsUrl = 'https://bsky.social',
  });

  final String accessJwt;
  final String refreshJwt;
  final String did;
  final String handle;
  final String pdsUrl;

  Map<String, dynamic> toJson() => {
        'accessJwt': accessJwt,
        'refreshJwt': refreshJwt,
        'did': did,
        'handle': handle,
        'pdsUrl': pdsUrl,
      };

  factory BlueskyCredentials.fromJson(Map<String, dynamic> json) {
    return BlueskyCredentials(
      accessJwt: json['accessJwt'] as String,
      refreshJwt: json['refreshJwt'] as String,
      did: json['did'] as String,
      handle: json['handle'] as String,
      pdsUrl: json['pdsUrl'] as String? ?? 'https://bsky.social',
    );
  }

  BlueskyCredentials copyWith({
    String? accessJwt,
    String? refreshJwt,
  }) {
    return BlueskyCredentials(
      accessJwt: accessJwt ?? this.accessJwt,
      refreshJwt: refreshJwt ?? this.refreshJwt,
      did: did,
      handle: handle,
      pdsUrl: pdsUrl,
    );
  }
}

/// X (Twitter) の認証情報
class XCredentials {
  const XCredentials({
    required this.authToken,
    required this.ct0,
  });

  final String authToken;
  final String ct0;

  Map<String, dynamic> toJson() => {
        'authToken': authToken,
        'ct0': ct0,
      };

  factory XCredentials.fromJson(Map<String, dynamic> json) {
    return XCredentials(
      authToken: json['authToken'] as String,
      ct0: json['ct0'] as String,
    );
  }
}

/// SNS アカウント
class Account {
  Account({
    required this.id,
    required this.service,
    required this.displayName,
    required this.handle,
    this.avatarUrl,
    required this.credentials,
    required this.createdAt,
    this.isEnabled = true,
  });

  final String id;
  final SnsService service;
  final String displayName;
  final String handle;
  final String? avatarUrl;

  /// BlueskyCredentials | XCredentials
  final Object credentials;
  final DateTime createdAt;
  final bool isEnabled;

  BlueskyCredentials get blueskyCredentials => credentials as BlueskyCredentials;
  XCredentials get xCredentials => credentials as XCredentials;

  Map<String, dynamic> toJson() {
    final credsJson = switch (credentials) {
      BlueskyCredentials c => c.toJson(),
      XCredentials c => c.toJson(),
      _ => throw StateError('Unknown credentials type'),
    };

    return {
      'id': id,
      'service': service.name,
      'displayName': displayName,
      'handle': handle,
      'avatarUrl': avatarUrl,
      'credentials': json.encode(credsJson),
      'createdAt': createdAt.toIso8601String(),
      'isEnabled': isEnabled,
    };
  }

  factory Account.fromJson(Map<String, dynamic> map) {
    final service = SnsService.values.firstWhere(
      (s) => s.name == map['service'],
    );
    final credsMap = json.decode(map['credentials'] as String)
        as Map<String, dynamic>;

    final Object creds = switch (service) {
      SnsService.bluesky => BlueskyCredentials.fromJson(credsMap),
      SnsService.x => XCredentials.fromJson(credsMap),
    };

    return Account(
      id: map['id'] as String,
      service: service,
      displayName: map['displayName'] as String,
      handle: map['handle'] as String,
      avatarUrl: map['avatarUrl'] as String?,
      credentials: creds,
      createdAt: DateTime.parse(map['createdAt'] as String),
      isEnabled: map['isEnabled'] as bool? ?? true,
    );
  }

  Account copyWith({
    Object? credentials,
    bool? isEnabled,
  }) {
    return Account(
      id: id,
      service: service,
      displayName: displayName,
      handle: handle,
      avatarUrl: avatarUrl,
      credentials: credentials ?? this.credentials,
      createdAt: createdAt,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }
}
