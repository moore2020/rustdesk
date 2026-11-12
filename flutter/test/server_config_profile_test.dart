import 'dart:convert';

import 'package:flutter_hbb/models/server_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('empty or invalid store creates one default with a stable saved ID', () {
    for (final encoded in ['', 'not JSON', '[]', '{"version":2}']) {
      final store = ServerProfileStore.decode(encoded);
      expect(store.profiles, hasLength(1));
      expect(store.defaultProfile.name, 'Default');
      expect(store.defaultProfileId, store.defaultProfile.id);
      expect(store.defaultProfile.id, isNotEmpty);

      final restored = ServerProfileStore.decode(store.encode());
      expect(restored.profiles, hasLength(1));
      expect(restored.defaultProfileId, store.defaultProfileId);
      expect(restored.defaultProfile.toJson(), store.defaultProfile.toJson());
    }
  });

  test('legacy migration copies all four values and round-trips only once', () {
    final legacy = {
      'custom-rendezvous-server': 'id.example.test',
      'relay-server': 'relay.example.test',
      'api-server': 'https://api.example.test',
      'key': ' literal+key/with=padding ',
    };
    final migrated = ServerProfileStore.fromLegacy(legacy);
    expect(migrated.profiles, hasLength(1));
    expect(migrated.defaultProfile.name, 'Default');
    expect(migrated.defaultProfile.idServer, legacy['custom-rendezvous-server']);
    expect(migrated.defaultProfile.relayServer, legacy['relay-server']);
    expect(migrated.defaultProfile.apiServer, legacy['api-server']);
    expect(migrated.defaultProfile.key, legacy['key']);

    legacy['custom-rendezvous-server'] = 'changed.example.test';
    final decoded = ServerProfileStore.decode(migrated.encode());
    expect(decoded.profiles, hasLength(1));
    expect(decoded.defaultProfile.toJson(), migrated.defaultProfile.toJson());
  });

  test('invalid entries and duplicate IDs do not replace valid profiles', () {
    final first = ServerProfile(id: 'first', name: 'First', idServer: 'one');
    final second = ServerProfile(id: 'second', name: 'Second', idServer: 'two');
    final duplicate = first.copyWith(name: 'Duplicate', idServer: 'ignored');
    final profiles = [
      null,
      {'id': 'incomplete'},
      {...first.toJson(), 'relayServer': 1},
      first.toJson(),
      duplicate.toJson(),
      second.toJson(),
    ];
    for (final defaultId in [null, 'missing', 'second']) {
      final store = ServerProfileStore.decode(jsonEncode({
        'version': 1,
        if (defaultId != null) 'defaultProfileId': defaultId,
        'profiles': profiles,
      }));
      expect(store.profiles.map((profile) => profile.id), ['first', 'second']);
      expect(store.profiles.first.name, 'First');
      expect(store.defaultProfile.id, defaultId == 'second' ? 'second' : 'first');
      expect(store.profileForPeer('missing').id, store.defaultProfile.id);
      expect(store.profileForPeer(null).id, store.defaultProfile.id);
      expect(store.profileForPeer('second').id, 'second');
    }
  });

  test('creating and editing profiles keeps existing IDs and snapshots stable',
      () {
    final store = ServerProfileStore.decode('');
    final added = ServerProfile.create(name: 'Added', idServer: 'new');
    final expanded = store.addProfile(added);
    expect(expanded.profiles, hasLength(2));
    expect(expanded.defaultProfileId, store.defaultProfileId);
    expect(added.id, isNot(store.defaultProfileId));

    final snapshot = ServerProfileSnapshot.fromProfile(added);
    final edited = expanded.updateProfile(
      added.copyWith(name: 'Renamed', idServer: 'changed'),
    );
    expect(edited.profileForPeer(added.id).name, 'Renamed');
    expect(edited.profileForPeer(added.id).idServer, 'changed');
    expect(edited.profileForPeer(added.id).id, added.id);
    expect(snapshot.name, 'Added');
    expect(snapshot.idServer, 'new');
    expect(expanded.profileForPeer(added.id).name, 'Added');
  });

  test('deletion clears known references and stale references use the default',
      () {
    final first = ServerProfile(id: 'first', name: 'First');
    final second = ServerProfile(id: 'second', name: 'Second');
    final store = ServerProfileStore(
      profiles: [first, second],
      defaultProfileId: 'first',
    );
    final preferences = {'peer-a': 'second', 'peer-b': 'first'};
    final deleted = store.deleteProfile('second', peerProfileIds: preferences);
    expect(deleted.store.profiles, hasLength(1));
    expect(deleted.peerProfileIds, {'peer-a': '', 'peer-b': 'first'});
    expect(deleted.clearedPeerIds, ['peer-a']);
    expect(deleted.store.profileForPeer(deleted.peerProfileIds['peer-a']).id,
        'first');
    expect(deleted.store.profileForPeer('second').id, 'first');
    expect(preferences['peer-a'], 'second');
    expect(() => store.deleteProfile('first'), throwsArgumentError);
    expect(() => deleted.store.deleteProfile('first'), throwsArgumentError);

    final switched = store.setDefaultProfile('second');
    expect(switched.deleteProfile('first').store.defaultProfile.id, 'second');
  });

  test('snapshots preserve every field through JSON including literal keys', () {
    final profile = ServerProfile(
      id: 'literal',
      name: 'Literal',
      idServer: 'id.example.test',
      relayServer: '',
      apiServer: '',
      key: ' literal+key/with=padding\n',
    );
    final snapshot = ServerProfileSnapshot.fromProfile(profile);
    final restored =
        ServerProfileSnapshot.fromJson(jsonDecode(jsonEncode(snapshot)));
    expect(restored.toJson(), {
      'id': 'literal',
      'name': 'Literal',
      'idServer': 'id.example.test',
      'relayServer': '',
      'apiServer': '',
      'key': ' literal+key/with=padding\n',
    });
  });
}
