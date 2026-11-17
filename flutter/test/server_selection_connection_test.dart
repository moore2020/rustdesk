import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/formatter/id_formatter.dart';
import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/server_config.dart';
import 'package:flutter_hbb/utils/multi_window_manager.dart';
import 'package:flutter_test/flutter_test.dart';

class _ServerBinding extends Fake implements RustdeskImpl {
  final Map<String, String> options = {};
  final Map<String, Map<String, String>> peerOptions = {};
  final List<String> peerWrites = [];

  @override
  String mainGetOptionSync({required String key, dynamic hint}) =>
      options[key] ?? '';

  @override
  Future<String> mainGetOptions({dynamic hint}) async => jsonEncode(options);

  @override
  Future<void> mainSetOption(
      {required String key, required String value, dynamic hint}) async {
    options[key] = value;
  }

  @override
  String mainGetPeerOptionSync(
          {required String id, required String key, dynamic hint}) =>
      peerOptions[id]?[key] ?? '';

  @override
  Future<void> mainSetPeerOption(
      {required String id,
      required String key,
      required String value,
      dynamic hint}) async {
    peerWrites.add('$id/$key=$value');
    (peerOptions[id] ??= {})[key] = value;
  }
}

ServerProfileStore _twoProfileStore() {
  const defaultProfile = ServerProfile(
    id: 'default-id',
    name: 'Default',
    idServer: 'default.example.test',
    relayServer: 'default-relay.example.test',
    apiServer: 'https://default-api.example.test',
    key: 'default-key',
  );
  const peerProfile = ServerProfile(
    id: 'peer-profile-id',
    name: 'Peer profile',
    idServer: 'peer.example.test',
    relayServer: '',
    apiServer: '',
    key: ' peer-key ',
  );
  return ServerProfileStore(
    profiles: [defaultProfile, peerProfile],
    defaultProfileId: 'default-id',
  );
}

void main() {
  group('isExplicitServerId', () {
    test('treats plain peer IDs as profile-eligible', () {
      for (final id in ['123456789', 'peer-id', '']) {
        expect(isExplicitServerId(id), isFalse, reason: id);
      }
    });

    test('bypasses explicit server, relay, IP and domain port forms', () {
      for (final id in [
        '123@server.example.test',
        '123@server.example.test?key=abc',
        '123/r',
        r'123\r',
        '192.168.1.10',
        'example.com:21116',
        '::1',
        ' 123 @server.example.test ',
      ]) {
        expect(isExplicitServerId(id), isTrue, reason: id);
      }
    });
  });

  group('resolveServerProfileForId', () {
    test('pure ID without preference resolves the default profile', () {
      final store = _twoProfileStore();
      final snapshot = resolveServerProfileForId(store, 'peer-a', null);

      expect(snapshot?.toJson(), store.defaultProfile.toJson());
      expect(snapshot?.id, 'default-id');
      expect(snapshot?.name, 'Default');
      expect(snapshot?.idServer, 'default.example.test');
      expect(snapshot?.relayServer, 'default-relay.example.test');
      expect(snapshot?.apiServer, 'https://default-api.example.test');
      expect(snapshot?.key, 'default-key');
    });

    test('pure ID with a valid preference resolves that profile', () {
      final store = _twoProfileStore();
      final snapshot =
          resolveServerProfileForId(store, 'peer-a', 'peer-profile-id');

      expect(snapshot?.id, 'peer-profile-id');
      expect(snapshot?.name, 'Peer profile');
      expect(snapshot?.idServer, 'peer.example.test');
      expect(snapshot?.relayServer, '');
      expect(snapshot?.apiServer, '');
      expect(snapshot?.key, ' peer-key ');
    });

    test('missing or deleted preference falls back to the default', () {
      final store = _twoProfileStore();
      for (final staleId in ['deleted-id', 'other', null]) {
        final snapshot = resolveServerProfileForId(store, 'peer-a', staleId);
        expect(snapshot?.id, store.defaultProfileId);
      }
      expect(store.encode(), _twoProfileStore().encode());
    });

    test('explicit forms bypass profile selection', () {
      final store = _twoProfileStore();
      for (final id in [
        '123@server.example.test',
        '123/r',
        r'123\r',
        '192.168.1.10',
        'example.com:21116',
      ]) {
        expect(
          resolveServerProfileForId(store, id, 'peer-profile-id'),
          isNull,
          reason: id,
        );
      }
    });

    test('selection only changes the returned snapshot, not the store', () {
      final store = _twoProfileStore();
      final before = store.encode();
      final first = resolveServerProfileForId(store, 'peer-a', null);
      final second =
          resolveServerProfileForId(store, 'peer-a', 'peer-profile-id');

      expect(first?.id, isNot(second?.id));
      expect(store.encode(), before);
    });
  });

  group('resolveDesktopServerProfile', () {
    late _ServerBinding binding;

    setUp(() {
      binding = _ServerBinding();
      platformFFI.setBindingForTesting(binding);
      binding.options[kServerProfileStoreOption] = _twoProfileStore().encode();
    });

    test('reads the peer preference without writing it back', () async {
      binding.peerOptions['peer-a'] = {
        kServerProfilePeerOption: 'peer-profile-id'
      };

      final snapshot = await resolveDesktopServerProfile('peer-a');

      expect(snapshot?.id, 'peer-profile-id');
      expect(binding.peerWrites, isEmpty);
    });

    test('uses the default profile when the preference is missing', () async {
      final snapshot = await resolveDesktopServerProfile('peer-a');

      expect(snapshot?.id, 'default-id');
      expect(binding.peerWrites, isEmpty);
    });

    test('does not read or write preferences for explicit forms', () async {
      binding.peerOptions['123@server.example.test'] = {
        kServerProfilePeerOption: 'peer-profile-id'
      };

      expect(await resolveDesktopServerProfile('123@server.example.test'),
          isNull);
      expect(await resolveDesktopServerProfile('123/r'), isNull);
      expect(await resolveDesktopServerProfile('192.168.1.10'), isNull);
      expect(binding.peerWrites, isEmpty);
    });
  });

  group('profile preference lifecycle', () {
    late _ServerBinding binding;

    setUp(() {
      binding = _ServerBinding();
      platformFFI.setBindingForTesting(binding);
      binding.options[kServerProfileStoreOption] = _twoProfileStore().encode();
    });

    test('only an existing profile with a pure peer ID may be persisted', () {
      final store = _twoProfileStore();
      expect(
        serverProfileIdForSuccess(
            peerId: 'peer-a',
            pendingProfileId: 'peer-profile-id',
            store: store),
        'peer-profile-id',
      );
      for (final id in [
        '123@server.example.test',
        '123/r',
        r'123\r',
        '192.168.1.10',
        'example.com:21116',
      ]) {
        expect(
          serverProfileIdForSuccess(
              peerId: id,
              pendingProfileId: 'peer-profile-id',
              store: store),
          isNull,
          reason: id,
        );
      }
      expect(
        serverProfileIdForSuccess(
            peerId: 'peer-a', pendingProfileId: null, store: store),
        isNull,
      );
      expect(
        serverProfileIdForSuccess(
            peerId: 'peer-a', pendingProfileId: '', store: store),
        isNull,
      );
      expect(
        serverProfileIdForSuccess(
            peerId: 'peer-a', pendingProfileId: 'deleted-id', store: store),
        isNull,
      );
    });

    test('saving writes only a valid pure-ID preference', () async {
      expect(
          await savePeerServerProfileId('peer-a', 'peer-profile-id'), isTrue);
      expect(readPeerServerProfileId('peer-a'), 'peer-profile-id');

      expect(await savePeerServerProfileId('peer-b', 'deleted-id'), isFalse);
      expect(
          await savePeerServerProfileId(
              '123@server.example.test', 'peer-profile-id'),
          isFalse);
      expect(binding.peerWrites, [
        'peer-a/$kServerProfilePeerOption=peer-profile-id',
      ]);
    });

    test('the last authenticated success wins and repeats are stable',
        () async {
      await savePeerServerProfileId('peer-a', 'default-id');
      await savePeerServerProfileId('peer-a', 'peer-profile-id');
      expect(readPeerServerProfileId('peer-a'), 'peer-profile-id');

      await savePeerServerProfileId('peer-a', 'peer-profile-id');
      expect(readPeerServerProfileId('peer-a'), 'peer-profile-id');

      await savePeerServerProfileId('peer-a', 'default-id');
      expect(readPeerServerProfileId('peer-a'), 'default-id');
    });
  });

  group('desktop entry point matrix', () {
    test('RDP and camera windows carry the resolved snapshot', () {
      final snapshot = ServerProfileSnapshot.fromProfile(
          _twoProfileStore().profiles[1]);
      final payload = snapshot.toJson();
      for (final params in [
        buildNewSessionParams(WindowType.RemoteDesktop, 'peer-a',
            serverProfile: payload),
        buildNewSessionParams(WindowType.ViewCamera, 'peer-a',
            serverProfile: payload),
        buildNewSessionParams(WindowType.PortForward, 'peer-a',
            isRDP: true, serverProfile: payload),
        buildNewSessionParams(WindowType.PortForward, 'peer-a',
            isRDP: false, serverProfile: payload),
      ]) {
        expect(params['serverProfile'], payload);
      }
    });
  });

  group('window parameters', () {
    final serverProfile = ServerProfileSnapshot.fromProfile(
        _twoProfileStore().profiles[1]);

    test('every desktop session type serializes the same profile payload', () {
      final expected = serverProfile.toJson();
      for (final type in [
        WindowType.RemoteDesktop,
        WindowType.FileTransfer,
        WindowType.ViewCamera,
        WindowType.PortForward,
        WindowType.Terminal,
      ]) {
        final params = buildNewSessionParams(
          type,
          'peer-a',
          password: 'secret',
          loginMethod: 'request-approval',
          forceRelay: false,
          switchUuid: 'switch-uuid',
          isRDP: true,
          isSharedPassword: true,
          connToken: 'token',
          serverProfile: expected,
        );
        expect(params['serverProfile'], expected, reason: type.name);
        expect(params['id'], 'peer-a');
        expect(params['password'], 'secret');
        expect(params['loginMethod'], 'request-approval');
        expect(params['forceRelay'], isFalse);
        expect(params['switch_uuid'], 'switch-uuid');
        expect(params['isRDP'], isTrue);
        expect(params['isSharedPassword'], isTrue);
        expect(params['connToken'], 'token');
      }
    });

    test('omitting the snapshot keeps the legacy payload unchanged', () {
      final params = buildNewSessionParams(
        WindowType.RemoteDesktop,
        'peer-a',
        forceRelay: true,
      );

      expect(params.containsKey('serverProfile'), isFalse);
      expect(params['forceRelay'], isTrue);
      expect(params['id'], 'peer-a');
    });

    test('tab moves reuse the session and carry no second profile', () {
      final params = buildTabMoveParams(
        WindowType.RemoteDesktop,
        'peer-a',
        'session-id',
        7,
      );

      expect(params, {
        'type': WindowType.RemoteDesktop.index,
        'id': 'peer-a',
        'tab_window_id': 7,
        'session_id': 'session-id',
      });
    });

    test('a window profile param is parsed back into a complete snapshot', () {
      final parsed = serverProfileFromWindowParam(serverProfile.toJson());

      expect(parsed?.toJson(), serverProfile.toJson());
      expect(serverProfileFromWindowParam(null), isNull);
      expect(serverProfileFromWindowParam('server'), isNull);
      expect(serverProfileFromWindowParam({'id': 'incomplete'}), isNull);
    });
  });

  testWidgets(
      'updateTextAndPreserveSelection keeps collapsed cursor while typing on macOS',
      (tester) async {
    final idController = IDTextEditingController();
    final fieldController = TextEditingController();
    addTearDown(() {
      idController.dispose();
      fieldController.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              updateTextAndPreserveSelection(
                  fieldController, idController.text);
              return TextField(
                controller: fieldController,
                inputFormatters: [IDTextInputFormatter()],
                onChanged: (v) => setState(() => idController.id = v),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: '1',
      selection: TextSelection.collapsed(offset: 1),
    ));
    await tester.pump();
    await tester.pump(Duration.zero);

    expect(fieldController.text, '1');
    expect(fieldController.selection, const TextSelection.collapsed(offset: 1));

    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: '12',
      selection: TextSelection.collapsed(offset: 2),
    ));
    await tester.pump();
    await tester.pump(Duration.zero);

    expect(fieldController.text, '12');
    expect(fieldController.selection, const TextSelection.collapsed(offset: 2));
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
