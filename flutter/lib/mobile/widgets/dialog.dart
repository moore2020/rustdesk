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
  OverlayDialogManager dialogManager, {
  ServerProfile? profile,
  required ServerProfileValidator validate,
}) {
  final form = _ServerProfileEditorForm(profile: profile, validate: validate);
  var closed = false;
  return dialogManager.show<ServerProfileDraft>((setState, close, context) {
    void cancel() {
      if (closed) return;
      closed = true;
      close();
    }

    void save(ServerProfileDraft draft) {
      if (closed) return;
      closed = true;
      close(draft);
    }

    return form.buildDialog(
      setState: setState,
      onSaved: save,
      onCancel: cancel,
      isActive: () => !closed,
    );
  }, backDismiss: false);
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
  late final _ServerProfileEditorForm _form;

  @override
  void initState() {
    super.initState();
    _form = _ServerProfileEditorForm(
      profile: widget.profile,
      validate: widget.validate,
    );
  }

  @override
  void dispose() {
    _form.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _form.buildDialog(
      setState: setState,
      onSaved: widget.onSaved,
      onCancel: widget.onCancel,
      isActive: () => mounted,
    );
  }
}

class _ServerProfileEditorForm {
  _ServerProfileEditorForm({
    required this.profile,
    required this.validate,
  }) {
    final config =
        profile == null ? ServerConfig() : ServerConfig.fromProfile(profile!);
    nameCtrl = TextEditingController(text: profile?.name ?? '');
    idCtrl = TextEditingController(text: config.idServer);
    relayCtrl = TextEditingController(text: config.relayServer);
    apiCtrl = TextEditingController(text: config.apiServer);
    keyCtrl = TextEditingController(text: config.key);
  }

  final ServerProfile? profile;
  final ServerProfileValidator validate;
  late final TextEditingController nameCtrl;
  late final TextEditingController idCtrl;
  late final TextEditingController relayCtrl;
  late final TextEditingController apiCtrl;
  late final TextEditingController keyCtrl;
  final errMsgs = [''.obs, ''.obs, ''.obs];
  var nameError = '';
  var saving = false;

  void dispose() {
    nameCtrl.dispose();
    idCtrl.dispose();
    relayCtrl.dispose();
    apiCtrl.dispose();
    keyCtrl.dispose();
  }

  CustomAlertDialog buildDialog({
    required void Function(VoidCallback) setState,
    required ValueChanged<ServerProfileDraft> onSaved,
    required VoidCallback onCancel,
    required bool Function() isActive,
  }) {
    Future<void> submit() async {
      if (saving) return;
      final name = nameCtrl.text.trim();
      if (name.isEmpty) {
        setState(() {
          nameError = translate('Failed');
        });
        return;
      }
      final config = ServerConfig(
        idServer: idCtrl.text,
        relayServer: relayCtrl.text,
        apiServer: apiCtrl.text,
        key: keyCtrl.text,
      );
      setState(() {
        nameError = '';
        saving = true;
      });
      final valid = await validate(name, config, errMsgs);
      if (!isActive()) return;
      setState(() {
        saving = false;
      });
      if (!valid) {
        showToast(translate('Failed'));
        return;
      }
      onSaved(ServerProfileDraft(name: name, config: config));
    }

    final controllers = [idCtrl, relayCtrl, apiCtrl, keyCtrl];
    return CustomAlertDialog(
      title: Row(
        children: [
          Expanded(
            child: Text(translate(profile == null ? 'Add' : 'Edit')),
          ),
          ...ServerConfigImportExportWidgets(
            controllers,
            errMsgs,
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
                nameCtrl,
                nameError,
                autofocus: true,
              ),
              const SizedBox(height: 8),
              _serverSettingsField(
                translate('ID Server'),
                idCtrl,
                errMsgs[0].value,
              ),
              const SizedBox(height: 8),
              _serverSettingsField(
                translate('Relay Server'),
                relayCtrl,
                errMsgs[1].value,
              ),
              const SizedBox(height: 8),
              _serverSettingsField(
                translate('API Server'),
                apiCtrl,
                errMsgs[2].value,
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
                  controller: apiCtrl,
                  idController: idCtrl,
                  message: translate('api_server_connection_tip'),
                  emptyMessage: translate('api_server_empty_tip'),
                ),
              ),
              const SizedBox(height: 8),
              _serverSettingsField('Key', keyCtrl, ''),
              if (saving)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(),
                ),
            ],
          ),
        ),
      ),
      actions: [
        dialogButton('Cancel', onPressed: onCancel, isOutline: true),
        dialogButton('OK', onPressed: saving ? null : submit),
      ],
      onSubmit: saving ? null : submit,
      onCancel: onCancel,
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

  var closed = false;
  dialogManager.show((setState, close, context) {
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
        dialogManager,
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
        dialogManager,
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

    Widget buildProfileTile(int index) {
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var index = 0; index < store.profiles.length; index++) ...[
                if (index > 0) const Divider(height: 1),
                buildProfileTile(index),
              ],
            ],
          ),
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
