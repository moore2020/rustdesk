import 'dart:convert';

import 'package:uuid/uuid.dart';

class ServerProfile {
  final String id;
  final String name;
  final String idServer;
  final String relayServer;
  final String apiServer;
  final String key;

  const ServerProfile({
    required this.id,
    required this.name,
    this.idServer = '',
    this.relayServer = '',
    this.apiServer = '',
    this.key = '',
  });

  factory ServerProfile.create({
    required String name,
    String idServer = '',
    String relayServer = '',
    String apiServer = '',
    String key = '',
  }) =>
      ServerProfile(
        id: Uuid().v4(),
        name: name,
        idServer: idServer,
        relayServer: relayServer,
        apiServer: apiServer,
        key: key,
      );

  factory ServerProfile.fromJson(Map<String, dynamic> json) {
    const fields = ['id', 'name', 'idServer', 'relayServer', 'apiServer', 'key'];
    if (fields.any((field) => json[field] is! String) ||
        (json['id'] as String).trim().isEmpty ||
        (json['name'] as String).trim().isEmpty) {
      throw const FormatException('Invalid server profile');
    }
    return ServerProfile(
      id: json['id'],
      name: json['name'],
      idServer: json['idServer'],
      relayServer: json['relayServer'],
      apiServer: json['apiServer'],
      key: json['key'],
    );
  }

  ServerProfile copyWith({
    String? name,
    String? idServer,
    String? relayServer,
    String? apiServer,
    String? key,
  }) =>
      ServerProfile(
        id: id,
        name: name ?? this.name,
        idServer: idServer ?? this.idServer,
        relayServer: relayServer ?? this.relayServer,
        apiServer: apiServer ?? this.apiServer,
        key: key ?? this.key,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'idServer': idServer,
        'relayServer': relayServer,
        'apiServer': apiServer,
        'key': key,
      };
}

class ServerProfileSnapshot extends ServerProfile {
  const ServerProfileSnapshot({
    required super.id,
    required super.name,
    required super.idServer,
    required super.relayServer,
    required super.apiServer,
    required super.key,
  });

  factory ServerProfileSnapshot.fromProfile(ServerProfile profile) =>
      ServerProfileSnapshot(
        id: profile.id,
        name: profile.name,
        idServer: profile.idServer,
        relayServer: profile.relayServer,
        apiServer: profile.apiServer,
        key: profile.key,
      );

  factory ServerProfileSnapshot.fromJson(Map<String, dynamic> json) =>
      ServerProfileSnapshot.fromProfile(ServerProfile.fromJson(json));
}

class ServerProfileStore {
  static const version = 1;

  final List<ServerProfile> profiles;
  final String defaultProfileId;

  ServerProfileStore({
    required Iterable<ServerProfile> profiles,
    required this.defaultProfileId,
  }) : profiles = List.unmodifiable(profiles) {
    final ids = <String>{};
    if (this.profiles.isEmpty ||
        this.profiles.any((profile) =>
            profile.id.trim().isEmpty ||
            profile.name.trim().isEmpty ||
            !ids.add(profile.id)) ||
        !ids.contains(defaultProfileId)) {
      throw ArgumentError('Invalid server profile store');
    }
  }

  factory ServerProfileStore.fromLegacy(Map<String, dynamic> options) {
    String value(String key) => options[key] is String ? options[key] : '';
    final profile = ServerProfile.create(
      name: 'Default',
      idServer: value('custom-rendezvous-server'),
      relayServer: value('relay-server'),
      apiServer: value('api-server'),
      key: value('key'),
    );
    return ServerProfileStore(profiles: [profile], defaultProfileId: profile.id);
  }

  factory ServerProfileStore.decode(String encoded) {
    return ServerProfileStore.tryDecode(encoded) ??
        ServerProfileStore.fromLegacy({});
  }

  /// Decodes [encoded], returning null when it is empty, malformed, or
  /// contains no valid profile.
  ///
  /// Unlike [decode], this never fabricates a legacy default, so callers can
  /// tell "nothing persisted yet" apart from a real store.
  static ServerProfileStore? tryDecode(String encoded) {
    if (encoded.isEmpty) {
      return null;
    }
    dynamic json;
    try {
      json = jsonDecode(encoded);
    } on FormatException {
      return null;
    }
    final profiles = <ServerProfile>[];
    final ids = <String>{};
    if (json is Map<String, dynamic> &&
        json['version'] == version &&
        json['profiles'] is List) {
      for (final entry in json['profiles']) {
        if (entry is! Map<String, dynamic>) {
          continue;
        }
        try {
          final profile = ServerProfile.fromJson(entry);
          if (ids.add(profile.id)) {
            profiles.add(profile);
          }
        } on FormatException {
          continue;
        }
      }
    }
    if (profiles.isEmpty) {
      return null;
    }
    final defaultId = json['defaultProfileId'];
    return ServerProfileStore(
      profiles: profiles,
      defaultProfileId: ids.contains(defaultId) ? defaultId : profiles.first.id,
    );
  }

  String encode() => jsonEncode({
        'version': version,
        'defaultProfileId': defaultProfileId,
        'profiles': profiles.map((profile) => profile.toJson()).toList(),
      });

  ServerProfile get defaultProfile =>
      profiles.firstWhere((profile) => profile.id == defaultProfileId);

  ServerProfile profileForPeer(String? profileId) => profiles.firstWhere(
        (profile) => profile.id == profileId,
        orElse: () => defaultProfile,
      );

  /// Snapshot of [profileId] as currently stored, or null when that profile no
  /// longer exists.
  ///
  /// Unlike [profileForPeer], this never falls back to the default, so a page
  /// holding a selection that was deleted in Settings re-resolves instead of
  /// silently connecting with a profile it no longer shows.
  ServerProfileSnapshot? snapshotForSelection(String? profileId) {
    if (profileId == null) {
      return null;
    }
    for (final profile in profiles) {
      if (profile.id == profileId) {
        return ServerProfileSnapshot.fromProfile(profile);
      }
    }
    return null;
  }

  ServerProfileStore addProfile(ServerProfile profile) => ServerProfileStore(
        profiles: [...profiles, profile],
        defaultProfileId: defaultProfileId,
      );

  ServerProfileStore updateProfile(ServerProfile profile) {
    if (!profiles.any((existing) => existing.id == profile.id)) {
      throw ArgumentError('Server profile does not exist');
    }
    return ServerProfileStore(
      profiles: profiles
          .map((existing) => existing.id == profile.id ? profile : existing),
      defaultProfileId: defaultProfileId,
    );
  }

  ServerProfileStore setDefaultProfile(String id) => ServerProfileStore(
        profiles: profiles,
        defaultProfileId: id,
      );

  ServerProfileDeletion deleteProfile(
    String id, {
    Map<String, String> peerProfileIds = const {},
  }) {
    if (profiles.length == 1 || id == defaultProfileId) {
      throw ArgumentError('Set another server profile as default first');
    }
    if (!profiles.any((profile) => profile.id == id)) {
      throw ArgumentError('Server profile does not exist');
    }
    final remainingPreferences = Map<String, String>.of(peerProfileIds);
    final clearedPeerIds = <String>[];
    for (final entry in peerProfileIds.entries) {
      if (entry.value == id) {
        remainingPreferences[entry.key] = '';
        clearedPeerIds.add(entry.key);
      }
    }
    return ServerProfileDeletion(
      store: ServerProfileStore(
        profiles: profiles.where((profile) => profile.id != id),
        defaultProfileId: defaultProfileId,
      ),
      peerProfileIds: remainingPreferences,
      clearedPeerIds: clearedPeerIds,
    );
  }
}

class ServerProfileDeletion {
  final ServerProfileStore store;
  final Map<String, String> peerProfileIds;
  final List<String> clearedPeerIds;

  ServerProfileDeletion({
    required this.store,
    required Map<String, String> peerProfileIds,
    required Iterable<String> clearedPeerIds,
  })  : peerProfileIds = Map.unmodifiable(peerProfileIds),
        clearedPeerIds = List.unmodifiable(clearedPeerIds);
}

/// Whether [rawId] carries its own transport target and must bypass the
/// configured server profiles.
///
/// Mirrors the forms handled by the legacy connection path: `id@server`,
/// forced-relay `id/r`, IP addresses, and `domain:port` direct connections.
/// A pure peer ID (including an empty input) resolves through the store.
bool isExplicitServerId(String rawId) {
  final id = rawId.replaceAll(RegExp(r'\s+'), '');
  if (id.isEmpty) {
    return false;
  }
  if (id.contains('@') || id.contains(':')) {
    return true;
  }
  if (id.endsWith(r'\r') || id.endsWith('/r')) {
    return true;
  }
  return _isIpv4Address(id);
}

bool _isIpv4Address(String id) {
  final parts = id.split('.');
  if (parts.length != 4) {
    return false;
  }
  for (final part in parts) {
    if (part.isEmpty || part.length > 3) {
      return false;
    }
    final value = int.tryParse(part);
    if (value == null || value < 0 || value > 255) {
      return false;
    }
  }
  return true;
}

/// The profile ID that may be remembered for [peerId] after an authenticated
/// success, or null when nothing should be written.
///
/// Only a pure peer ID has a meaningful profile preference, and a profile
/// deleted while the session was connecting must not leave a dangling ID.
String? serverProfileIdForSuccess({
  required String peerId,
  required String? pendingProfileId,
  required ServerProfileStore store,
}) {
  if (pendingProfileId == null || pendingProfileId.isEmpty) {
    return null;
  }
  if (isExplicitServerId(peerId)) {
    return null;
  }
  if (!store.profiles.any((profile) => profile.id == pendingProfileId)) {
    return null;
  }
  return pendingProfileId;
}

/// Resolves the server profile snapshot for a connection to [rawId].
///
/// A valid [peerProfileId] wins; a missing or deleted one falls back to the
/// store default. Explicit server forms return null so the legacy path keeps
/// full control. This never writes the peer preference.
ServerProfileSnapshot? resolveServerProfileForId(
  ServerProfileStore store,
  String rawId,
  String? peerProfileId,
) {
  if (isExplicitServerId(rawId)) {
    return null;
  }
  return ServerProfileSnapshot.fromProfile(store.profileForPeer(peerProfileId));
}

/// Whether [auditServer] is served by the globally configured API server.
///
/// The account access token belongs to that server only. A profile session may
/// be audited by another API server, so callers must not send the token there.
bool auditServerUsesGlobalApiServer({
  required String auditServer,
  required String globalApiServer,
}) {
  if (auditServer.isEmpty || globalApiServer.isEmpty) {
    return false;
  }
  return auditServer.startsWith('$globalApiServer/api/audit/');
}
