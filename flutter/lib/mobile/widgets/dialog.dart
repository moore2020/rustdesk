import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/api_server_warning.dart';
import 'package:flutter_hbb/common/widgets/setting_widgets.dart';
import 'package:flutter_hbb/common/widgets/toolbar.dart';
import 'package:get/get.dart';

import '../../common.dart';
import '../../models/peer_model.dart';
import '../../models/platform_model.dart';
import '../../models/server_config.dart';

void _showSuccess() {
  showToast(translate("Successful"));
}

void setTemporaryPasswordLengthDialog(
    OverlayDialogManager dialogManager) async {
  List<String> lengths = ['6', '8', '10'];
  String length = await bind.mainGetOption(key: "temporary-password-length");
  var index = lengths.indexOf(length);
  if (index < 0) index = 0;
  length = lengths[index];
  dialogManager.show((setState, close, context) {
    setLength(newValue) {
      final oldValue = length;
      if (oldValue == newValue) return;
      setState(() {
        length = newValue;
      });
      bind.mainSetOption(key: "temporary-password-length", value: newValue);
      bind.mainUpdateTemporaryPassword();
      Future.delayed(Duration(milliseconds: 200), () {
        close();
        _showSuccess();
      });
    }

    return CustomAlertDialog(
      title: Text(translate("Set one-time password length")),
      content: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: lengths
              .map(
                (value) => Row(
                  children: [
                    Text(value),
                    Radio(
                        value: value, groupValue: length, onChanged: setLength),
                  ],
                ),
              )
              .toList()),
    );
  }, backDismiss: true, clickMaskDismiss: true);
}

void showServerSettings(OverlayDialogManager dialogManager,
    void Function(VoidCallback) setState) async {
  Map<String, dynamic> options = {};
  try {
    options = jsonDecode(await bind.mainGetOptions());
  } catch (e) {
    print("Invalid server config: $e");
  }
  showServerSettingsWithValue(
      ServerConfig.fromOptions(options), dialogManager, setState);
}

const double _kServerSettingsLabelWidth = 120.0;
const double _kServerSettingsLabelSpacing = 8.0;

Widget _serverSettingsField(
    String label, TextEditingController controller, String errorMsg,
    {String? Function(String?)? validator, bool autofocus = false}) {
  if (isDesktop || isWeb) {
    return Row(
      children: [
        SizedBox(
          width: _kServerSettingsLabelWidth,
          child: Text(label),
        ),
        const SizedBox(width: _kServerSettingsLabelSpacing),
        Expanded(
          child: serverSettingsTextFormField(
            label: label,
            controller: controller,
            errorMsg: errorMsg,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            showLabelText: false,
            validator: validator,
            autofocus: autofocus,
          ).workaroundFreezeLinuxMint(),
        ),
      ],
    );
  }

  return serverSettingsTextFormField(
    label: label,
    controller: controller,
    errorMsg: errorMsg,
    validator: validator,
  ).workaroundFreezeLinuxMint();
}

void showServerSettingsWithValue(
    ServerConfig serverConfig,
    OverlayDialogManager dialogManager,
    void Function(VoidCallback)? upSetState) async {
  var isInProgress = false;
  final idCtrl = TextEditingController(text: serverConfig.idServer);
  final relayCtrl = TextEditingController(text: serverConfig.relayServer);
  final apiCtrl = TextEditingController(text: serverConfig.apiServer);
  final keyCtrl = TextEditingController(text: serverConfig.key);

  RxString idServerMsg = ''.obs;
  RxString relayServerMsg = ''.obs;
  RxString apiServerMsg = ''.obs;

  final controllers = [idCtrl, relayCtrl, apiCtrl, keyCtrl];
  final errMsgs = [
    idServerMsg,
    relayServerMsg,
    apiServerMsg,
  ];

  dialogManager.show((setState, close, context) {
    Future<bool> submit() async {
      setState(() {
        isInProgress = true;
      });
      bool ret = await setServerConfig(
          null,
          errMsgs,
          ServerConfig(
              idServer: idCtrl.text.trim(),
              relayServer: relayCtrl.text.trim(),
              apiServer: apiCtrl.text.trim(),
              key: keyCtrl.text.trim()));
      setState(() {
        isInProgress = false;
      });
      return ret;
    }

    return CustomAlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(translate('ID/Relay Server'))),
          ...ServerConfigImportExportWidgets(controllers, errMsgs),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 500),
        child: Form(
          child: Obx(() => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _serverSettingsField(
                      translate('ID Server'), idCtrl, idServerMsg.value,
                      autofocus: true),
                  SizedBox(height: 8),
                  if (!isIOS && !isWeb) ...[
                    _serverSettingsField(translate('Relay Server'), relayCtrl,
                        relayServerMsg.value),
                    SizedBox(height: 8),
                  ],
                  _serverSettingsField(
                    translate('API Server'),
                    apiCtrl,
                    apiServerMsg.value,
                    validator: (v) {
                      if (v != null && v.isNotEmpty) {
                        if (!(v.startsWith('http://') ||
                            v.startsWith("https://"))) {
                          return translate("invalid_http");
                        }
                      }
                      return null;
                    },
                  ),
                  Padding(
                    padding: EdgeInsetsDirectional.only(
                      start: isDesktop || isWeb
                          ? _kServerSettingsLabelWidth +
                              _kServerSettingsLabelSpacing
                          : 0,
                    ),
                    child: ApiServerWarning(
                      controller: apiCtrl,
                      idController: idCtrl,
                      message: translate('api_server_connection_tip'),
                      emptyMessage: translate('api_server_empty_tip'),
                    ),
                  ),
                  SizedBox(height: 8),
                  _serverSettingsField('Key', keyCtrl, ''),
                  if (isInProgress)
                    Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: LinearProgressIndicator(),
                    ),
                ],
              )),
        ),
      ),
      actions: [
        dialogButton('Cancel', onPressed: () {
          close();
        }, isOutline: true),
        dialogButton(
          'OK',
          onPressed: () async {
            if (await submit()) {
              close();
              showToast(translate('Successful'));
              upSetState?.call(() {});
            } else {
              showToast(translate('Failed'));
            }
          },
        ),
      ],
    );
  });
}

TextFormField serverSettingsTextFormField({
  required String label,
  required TextEditingController controller,
  required String errorMsg,
  String? Function(String?)? validator,
  bool autofocus = false,
  bool showLabelText = true,
  EdgeInsetsGeometry? contentPadding,
}) {
  return TextFormField(
    controller: controller,
    decoration: InputDecoration(
      labelText: showLabelText ? label : null,
      errorText: errorMsg.isEmpty ? null : errorMsg,
      contentPadding: contentPadding,
    ),
    validator: validator,
    autofocus: autofocus,
    keyboardType: TextInputType.visiblePassword,
    textCapitalization: TextCapitalization.none,
    autocorrect: false,
    enableSuggestions: false,
    smartDashesType: SmartDashesType.disabled,
    smartQuotesType: SmartQuotesType.disabled,
    enableIMEPersonalizedLearning: false,
    spellCheckConfiguration: const SpellCheckConfiguration.disabled(),
  );
}

class ServerProfileDraft {
  final String name;
  final ServerConfig config;

  const ServerProfileDraft({required this.name, required this.config});
}

typedef ServerProfileValidator = Future<bool> Function(
    String name, ServerConfig config, List<RxString> errMsgs);

Future<ServerProfileDraft?> showServerProfileEditor(
  BuildContext context, {
  ServerProfile? profile,
  required ServerProfileValidator validate,
}) {
  return showDialog<ServerProfileDraft>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => ServerProfileEditor(
      profile: profile,
      validate: validate,
      onCancel: () => Navigator.of(dialogContext).pop(),
      onSaved: (draft) => Navigator.of(dialogContext).pop(draft),
    ),
  );
}

class ServerProfileEditor extends StatefulWidget {
  const ServerProfileEditor({
    Key? key,
    this.profile,
    required this.validate,
    required this.onSaved,
    required this.onCancel,
  }) : super(key: key);

  final ServerProfile? profile;
  final ServerProfileValidator validate;
  final ValueChanged<ServerProfileDraft> onSaved;
  final VoidCallback onCancel;

  @override
  State<ServerProfileEditor> createState() => _ServerProfileEditorState();
}

class _ServerProfileEditorState extends State<ServerProfileEditor> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _idCtrl;
  late final TextEditingController _relayCtrl;
  late final TextEditingController _apiCtrl;
  late final TextEditingController _keyCtrl;
  final _errMsgs = [''.obs, ''.obs, ''.obs];
  var _nameError = '';
  var _saving = false;

  @override
  void initState() {
    super.initState();
    final config = widget.profile == null
        ? ServerConfig()
        : ServerConfig.fromProfile(widget.profile!);
    _nameCtrl = TextEditingController(text: widget.profile?.name ?? '');
    _idCtrl = TextEditingController(text: config.idServer);
    _relayCtrl = TextEditingController(text: config.relayServer);
    _apiCtrl = TextEditingController(text: config.apiServer);
    _keyCtrl = TextEditingController(text: config.key);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _idCtrl.dispose();
    _relayCtrl.dispose();
    _apiCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() {
        _nameError = translate('Failed');
      });
      return;
    }
    final config = ServerConfig(
      idServer: _idCtrl.text,
      relayServer: _relayCtrl.text,
      apiServer: _apiCtrl.text,
      key: _keyCtrl.text,
    );
    setState(() {
      _nameError = '';
      _saving = true;
    });
    final valid = await widget.validate(name, config, _errMsgs);
    if (!mounted) return;
    setState(() {
      _saving = false;
    });
    if (!valid) {
      showToast(translate('Failed'));
      return;
    }
    widget.onSaved(ServerProfileDraft(name: name, config: config));
  }

  @override
  Widget build(BuildContext context) {
    final controllers = [_idCtrl, _relayCtrl, _apiCtrl, _keyCtrl];
    return CustomAlertDialog(
      title: Row(
        children: [
          Expanded(
            child: Text(translate(widget.profile == null ? 'Add' : 'Edit')),
          ),
          ...ServerConfigImportExportWidgets(
            controllers,
            _errMsgs,
            writeGlobal: false,
            onImported: () => setState(() {}),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 500),
        child: Form(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _serverSettingsField(
                translate('Name'),
                _nameCtrl,
                _nameError,
                autofocus: true,
              ),
              const SizedBox(height: 8),
              _serverSettingsField(
                translate('ID Server'),
                _idCtrl,
                _errMsgs[0].value,
              ),
              const SizedBox(height: 8),
              _serverSettingsField(
                translate('Relay Server'),
                _relayCtrl,
                _errMsgs[1].value,
              ),
              const SizedBox(height: 8),
              _serverSettingsField(
                translate('API Server'),
                _apiCtrl,
                _errMsgs[2].value,
                validator: (value) {
                  if (value != null && value.isNotEmpty) {
                    if (!(value.startsWith('http://') ||
                        value.startsWith('https://'))) {
                      return translate("invalid_http");
                    }
                  }
                  return null;
                },
              ),
              Padding(
                padding: EdgeInsetsDirectional.only(
                  start: isDesktop || isWeb
                      ? _kServerSettingsLabelWidth +
                          _kServerSettingsLabelSpacing
                      : 0,
                ),
                child: ApiServerWarning(
                  controller: _apiCtrl,
                  idController: _idCtrl,
                  message: translate('api_server_connection_tip'),
                  emptyMessage: translate('api_server_empty_tip'),
                ),
              ),
              const SizedBox(height: 8),
              _serverSettingsField('Key', _keyCtrl, ''),
              if (_saving)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(),
                ),
            ],
          ),
        ),
      ),
      actions: [
        dialogButton('Cancel', onPressed: widget.onCancel, isOutline: true),
        dialogButton('OK', onPressed: _saving ? null : _submit),
      ],
      onSubmit: _saving ? null : _submit,
      onCancel: widget.onCancel,
    );
  }
}

Future<void> showServerProfiles(
  OverlayDialogManager dialogManager,
  void Function(VoidCallback) upSetState,
) async {
  ServerProfileStore store;
  try {
    store = await loadServerProfileStore();
  } catch (e) {
    debugPrint('Failed to load server profiles: $e');
    showToast(translate('Failed'));
    return;
  }

  dialogManager.show((setState, close, context) {
    var closed = false;

    void closeDialog() {
      closed = true;
      close();
    }

    void refresh(ServerProfileStore latest) {
      if (closed) return;
      setState(() {
        store = latest;
      });
      upSetState(() {});
    }

    Future<void> addProfile() async {
      final draft = await showServerProfileEditor(
        context,
        validate: (name, config, errMsgs) =>
            setServerConfig(null, errMsgs, config, writeGlobal: false),
      );
      if (draft == null || closed) return;
      final latest = await loadServerProfileStore();
      final updated = latest.addProfile(ServerProfile.create(
        name: draft.name,
        idServer: draft.config.idServer,
        relayServer: draft.config.relayServer,
        apiServer: draft.config.apiServer,
        key: draft.config.key,
      ));
      await saveServerProfileStore(updated);
      refresh(updated);
    }

    Future<void> editProfile(ServerProfile profile, bool isDefault) async {
      final draft = await showServerProfileEditor(
        context,
        profile: profile,
        validate: (name, config, errMsgs) => setServerConfig(
          null,
          errMsgs,
          config,
          writeGlobal: isDefault,
          profileId: profile.id,
        ),
      );
      if (draft == null || closed) return;
      final latest = await loadServerProfileStore();
      if (!latest.profiles.any((existing) => existing.id == profile.id)) {
        return;
      }
      final updated = latest.updateProfile(profile.copyWith(
        name: draft.name,
        idServer: draft.config.idServer,
        relayServer: draft.config.relayServer,
        apiServer: draft.config.apiServer,
        key: draft.config.key,
      ));
      await saveServerProfileStore(updated);
      refresh(updated);
    }

    Future<void> setDefault(ServerProfile profile) async {
      final errMsgs = [''.obs, ''.obs, ''.obs];
      final valid = await setServerConfig(
        null,
        errMsgs,
        serverConfigFromServerProfile(profile),
        profileId: profile.id,
      );
      if (closed) return;
      if (!valid) {
        showToast(translate('Failed'));
        return;
      }
      final latest = await loadServerProfileStore();
      if (!latest.profiles.any((existing) => existing.id == profile.id)) {
        return;
      }
      final updated = latest.setDefaultProfile(profile.id);
      await saveServerProfileStore(updated);
      refresh(updated);
    }

    Future<void> deleteProfile(ServerProfile profile) async {
      final latest = await loadServerProfileStore();
      if (latest.profiles.length <= 1 ||
          profile.id == latest.defaultProfileId) {
        showToast(translate('Failed'));
        return;
      }
      final peerIds = <String>{};
      void addPeers(Peers peers) {
        for (final peer in peers.peers) {
          if (peer.id.isNotEmpty) {
            peerIds.add(peer.id);
          }
        }
        for (final id in peers.restPeerIds) {
          if (id.isNotEmpty) {
            peerIds.add(id);
          }
        }
      }

      addPeers(gFFI.recentPeersModel);
      addPeers(gFFI.favoritePeersModel);
      addPeers(gFFI.lanPeersModel);
      final peerProfileIds = <String, String>{};
      for (final peerId in peerIds) {
        peerProfileIds[peerId] = readPeerServerProfileId(peerId) ?? '';
      }
      final deletion = latest.deleteProfile(
        profile.id,
        peerProfileIds: peerProfileIds,
      );
      await saveServerProfileStore(deletion.store);
      await clearPeerServerProfileIds(deletion.clearedPeerIds);
      refresh(deletion.store);
    }

    return CustomAlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(translate('ID/Relay Server'))),
          Tooltip(
            message: translate('Add'),
            child: IconButton(
              onPressed: addProfile,
              icon: const Icon(Icons.add),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 500, maxHeight: 400),
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: store.profiles.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final profile = store.profiles[index];
            final isDefault = profile.id == store.defaultProfileId;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Row(
                children: [
                  Flexible(
                    child: Text(
                      profile.name,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isDefault) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: MyTheme.accent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        translate('Default'),
                        style: TextStyle(fontSize: 12, color: MyTheme.accent),
                      ),
                    ),
                  ],
                ],
              ),
              subtitle: Text(
                profile.idServer.isEmpty ? '-' : profile.idServer,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!isDefault)
                    Tooltip(
                      message: translate('Default'),
                      child: IconButton(
                        onPressed: () => setDefault(profile),
                        icon: const Icon(Icons.star_border),
                      ),
                    ),
                  Tooltip(
                    message: translate('Edit'),
                    child: IconButton(
                      onPressed: () => editProfile(profile, isDefault),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  ),
                  if (!isDefault && store.profiles.length > 1)
                    Tooltip(
                      message: translate('Delete'),
                      child: IconButton(
                        onPressed: () => deleteProfile(profile),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                ],
              ),
              onTap: () => editProfile(profile, isDefault),
            );
          },
        ),
      ),
      actions: [
        dialogButton('Close', onPressed: closeDialog, isOutline: true),
      ],
      onCancel: closeDialog,
    );
  }, backDismiss: false);
}

void setPrivacyModeDialog(
  OverlayDialogManager dialogManager,
  List<TToggleMenu> privacyModeList,
  RxString privacyModeState,
) async {
  dialogManager.dismissAll();
  dialogManager.show((setState, close, context) {
    return CustomAlertDialog(
      title: Text(translate('Privacy mode')),
      content: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: privacyModeList
              .map((value) => CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    title: value.child,
                    value: value.value,
                    onChanged: value.onChanged,
                  ))
              .toList()),
    );
  }, backDismiss: true, clickMaskDismiss: true);
}
