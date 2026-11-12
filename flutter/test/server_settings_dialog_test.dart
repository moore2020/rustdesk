import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/mobile/widgets/dialog.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/server_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

class _ServerBinding extends Fake implements RustdeskImpl {
  final Map<String, String> options = {};
  final List<String> writtenOptionKeys = [];
  final List<String> testedServers = [];

  @override
  String translate(
          {required String name, required String locale, dynamic hint}) =>
      name;

  @override
  Future<String> mainTestIfValidServer(
      {required String server,
      required bool testWithProxy,
      dynamic hint}) async {
    testedServers.add(server);
    return server.contains('invalid') ? 'invalid_server' : '';
  }

  @override
  String mainGetCommonSync({required String key, dynamic hint}) =>
      '{"url":""}';

  @override
  String mainGetOptionSync({required String key, dynamic hint}) =>
      options[key] ?? '';

  @override
  Future<void> mainSetOption(
      {required String key, required String value, dynamic hint}) async {
    options[key] = value;
    writtenOptionKeys.add(key);
  }

  @override
  Future<String> mainGetOptions({dynamic hint}) async => jsonEncode(options);

  @override
  Future<String> mainGetApiServer({dynamic hint}) async => '';
}

Widget _profileEditor({
  ServerProfile? profile,
  required Future<bool> Function(
          String name, ServerConfig config, List<RxString> errMsgs)
      validate,
  required void Function(ServerProfileDraft draft) onSaved,
  VoidCallback? onCancel,
}) =>
    MaterialApp(
      home: Scaffold(
        body: ServerProfileEditor(
          profile: profile,
          validate: validate,
          onSaved: onSaved,
          onCancel: onCancel ?? () {},
        ),
      ),
    );

void main() {
  late _ServerBinding binding;

  setUp(() {
    binding = _ServerBinding();
    platformFFI.setBindingForTesting(binding);
  });

  testWidgets('server settings text fields preserve literal input',
      (tester) async {
    final controller = TextEditingController(text: 'AbCdR1c1E=');
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: serverSettingsTextFormField(
          label: 'Key',
          controller: controller,
          errorMsg: '',
          autofocus: true,
        ),
      ),
    ));

    final textField = tester.widget<TextField>(find.byType(TextField));

    expect(textField.controller, controller);
    expect(textField.autofocus, isTrue);
    expect(textField.keyboardType, TextInputType.visiblePassword);
    expect(textField.textCapitalization, TextCapitalization.none);
    expect(textField.autocorrect, isFalse);
    expect(textField.enableSuggestions, isFalse);
    expect(textField.smartDashesType, SmartDashesType.disabled);
    expect(textField.smartQuotesType, SmartQuotesType.disabled);
    expect(textField.enableIMEPersonalizedLearning, isFalse);
    expect(
      textField.spellCheckConfiguration,
      const SpellCheckConfiguration.disabled(),
    );
  });

  testWidgets('profile form loads every field without altering literal input',
      (tester) async {
    final profile = ServerProfile(
      id: 'profile-1',
      name: 'Office',
      idServer: 'id.example.test',
      relayServer: 'relay.example.test',
      apiServer: 'https://api.example.test',
      key: ' AbCdR1c1E= ',
    );

    await tester.pumpWidget(_profileEditor(
      profile: profile,
      validate: (name, config, errMsgs) async => true,
      onSaved: (_) {},
    ));
    // Flush the dialog's zero-duration focus timer.
    await tester.pump(Duration.zero);

    final fields =
        tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields, hasLength(5));
    expect(fields.map((field) => field.controller?.text), [
      'Office',
      'id.example.test',
      'relay.example.test',
      'https://api.example.test',
      ' AbCdR1c1E= ',
    ]);

    final keyField = fields.last;
    expect(keyField.keyboardType, TextInputType.visiblePassword);
    expect(keyField.textCapitalization, TextCapitalization.none);
    expect(keyField.autocorrect, isFalse);
    expect(keyField.enableSuggestions, isFalse);
    expect(
      keyField.spellCheckConfiguration,
      const SpellCheckConfiguration.disabled(),
    );
    expect(profile.toJson(), {
      'id': 'profile-1',
      'name': 'Office',
      'idServer': 'id.example.test',
      'relayServer': 'relay.example.test',
      'apiServer': 'https://api.example.test',
      'key': ' AbCdR1c1E= ',
    });
  });

  testWidgets('profile form validates servers and only returns edited values',
      (tester) async {
    final profile = ServerProfile(
      id: 'profile-1',
      name: 'Office',
      idServer: 'old-id.example.test',
    );
    ServerProfileDraft? saved;

    await tester.pumpWidget(_profileEditor(
      profile: profile,
      validate: (name, config, errMsgs) =>
          setServerConfig(null, errMsgs, config, writeGlobal: false),
      onSaved: (draft) => saved = draft,
    ));

    await tester.enterText(find.byType(TextField).at(0), 'Home');
    await tester.enterText(find.byType(TextField).at(1), 'invalid-id');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(binding.testedServers, ['invalid-id']);
    expect(find.text('invalid_server'), findsOneWidget);
    expect(saved, isNull);
    expect(profile.name, 'Office');
    expect(profile.idServer, 'old-id.example.test');
    expect(binding.writtenOptionKeys, isEmpty);

    await tester.enterText(
        find.byType(TextField).at(1), 'new-id.example.test');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(saved?.name, 'Home');
    expect(saved?.config.idServer, 'new-id.example.test');
    expect(profile.name, 'Office');
    expect(profile.idServer, 'old-id.example.test');
    expect(binding.writtenOptionKeys, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile form rejects an empty name before validating servers',
      (tester) async {
    ServerProfileDraft? saved;

    await tester.pumpWidget(_profileEditor(
      validate: (name, config, errMsgs) =>
          setServerConfig(null, errMsgs, config, writeGlobal: false),
      onSaved: (draft) => saved = draft,
    ));

    await tester.enterText(find.byType(TextField).at(1), 'id.example.test');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(saved, isNull);
    expect(binding.testedServers, isEmpty);
    expect(find.text('Failed'), findsOneWidget);
  });

  testWidgets('profile form keeps API URL validation', (tester) async {
    ServerProfileDraft? saved;

    await tester.pumpWidget(_profileEditor(
      validate: (name, config, errMsgs) =>
          setServerConfig(null, errMsgs, config, writeGlobal: false),
      onSaved: (draft) => saved = draft,
    ));

    await tester.enterText(find.byType(TextField).at(0), 'Office');
    await tester.enterText(
        find.byType(TextField).at(3), 'ftp://api.example.test');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(saved, isNull);
    expect(find.text('API Server: invalid_http'), findsOneWidget);
    expect(binding.writtenOptionKeys, isEmpty);
  });

  test('legacy server writes update only the default profile', () async {
    const defaultId = 'default-id';
    const otherId = 'other-id';
    final defaultProfile = ServerProfile(
      id: defaultId,
      name: 'Default',
      idServer: 'default.example.test',
    );
    final otherProfile = ServerProfile(
      id: otherId,
      name: 'Other',
      idServer: 'other.example.test',
    );
    binding.options[kServerProfileStoreOption] = ServerProfileStore(
      profiles: [defaultProfile, otherProfile],
      defaultProfileId: defaultId,
    ).encode();
    final errMsgs = [''.obs, ''.obs, ''.obs];

    final saved = await setServerConfig(
      null,
      errMsgs,
      ServerConfig(
        idServer: 'new.example.test/',
        relayServer: 'relay.example.test/',
        apiServer: 'https://api.example.test/',
        key: ' new-key ',
      ),
    );

    expect(saved, isTrue);
    final store =
        ServerProfileStore.decode(binding.options[kServerProfileStoreOption]!);
    expect(store.defaultProfile.id, defaultId);
    expect(store.defaultProfile.idServer, 'new.example.test');
    expect(store.defaultProfile.relayServer, 'relay.example.test');
    expect(store.defaultProfile.apiServer, 'https://api.example.test');
    expect(store.defaultProfile.key, 'new-key');
    expect(
      store.profiles.firstWhere((profile) => profile.id == otherId).toJson(),
      otherProfile.toJson(),
    );
    expect(binding.options['custom-rendezvous-server'], 'new.example.test');
    expect(binding.options['relay-server'], 'relay.example.test');
    expect(binding.options['api-server'], 'https://api.example.test');
    expect(binding.options['key'], 'new-key');
  });

  test('validation-only server writes leave options untouched', () async {
    binding.options['custom-rendezvous-server'] = 'old.example.test';
    final errMsgs = [''.obs, ''.obs, ''.obs];

    final saved = await setServerConfig(
      null,
      errMsgs,
      ServerConfig(idServer: 'valid.example.test', key: 'valid-key'),
      writeGlobal: false,
    );

    expect(saved, isTrue);
    expect(binding.testedServers, ['valid.example.test']);
    expect(binding.writtenOptionKeys, isEmpty);
    expect(binding.options['custom-rendezvous-server'], 'old.example.test');
  });
}
