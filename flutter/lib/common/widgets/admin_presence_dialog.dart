import 'dart:async';

import 'package:dynamic_layouts/dynamic_layouts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
import 'package:flutter_hbb/models/admin_presence_model.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

import '../../common.dart';
import '../../models/platform_model.dart';
import 'peer_card.dart';

/// Admin-presence customization for this Windows client version: embedded
/// tab-pane listing devices currently known to the self-hosted admin presence
/// API. Selecting an online device calls RustDesk's normal connection flow;
/// target password/consent/permissions are never bypassed.
class AdminPresencePane extends StatefulWidget {
  const AdminPresencePane({Key? key}) : super(key: key);

  @override
  State<AdminPresencePane> createState() => _AdminPresencePaneState();
}

class _AdminPresencePaneState extends State<AdminPresencePane> {
  late final AdminPresenceModel _model;
  Timer? _offlineTimer;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _model = AdminPresenceModel();
    bind.mainLoadRecentPeers();
    bind.mainLoadFavPeers();
    bind.mainLoadLanPeers();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshFromConfig());
    _offlineTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && !_model.loading) {
        _refreshFromConfig();
      }
    });
  }

  @override
  void dispose() {
    _offlineTimer?.cancel();
    _refreshTimer?.cancel();
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AdminPresenceModel>.value(
      value: _model,
      child: Consumer<AdminPresenceModel>(
        builder: (context, model, child) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: model.isLoggedIn
                ? _buildDeviceList(context, model)
                : _buildConfigurePrompt(context, model),
          );
        },
      ),
    );
  }

  Future<void> _refreshFromConfig() async {
    if (!mounted) return;
    if (!await _model.loginWithSavedToken()) return;
    await _model.refreshDevices();
  }

  /// Admin-presence customization: prompt users to configure the saved
  /// self-hosted admin API endpoint and token before showing device presence.
  Widget _buildConfigurePrompt(BuildContext context, AdminPresenceModel model) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              translate('Admin online devices'),
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              translate('Configure admin presence in Settings > Network'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (model.error != null)
              Text(
                model.error!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.center,
              child: Wrap(
                spacing: 8,
                children: [
                  ElevatedButton(
                    onPressed: () =>
                        DesktopSettingPage.switch2page(SettingsTabKey.network),
                    child: Text(translate('Open Settings')),
                  ),
                  OutlinedButton(
                    onPressed: model.loading ? null : _refreshFromConfig,
                    child: model.loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(translate('Retry')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Admin-presence customization: Recent Sessions-style list with server
  /// reachability, online/offline state, stale-device delete, and auto-refresh.
  Widget _buildDeviceList(BuildContext context, AdminPresenceModel model) {
    final onlineCount = model.devices.where((d) => d.online).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            getOnline(8, model.serverOnline),
            Expanded(
              child: Text(
                '${translate('Server')}: ${model.server}  -  '
                '$onlineCount/${model.devices.length} ${translate('Online')}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (model.loading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        if (model.error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(model.error!, style: const TextStyle(color: Colors.red)),
          ),
        Expanded(
          child: model.devices.isEmpty
              ? Center(child: Text(translate('No devices online')))
              // Admin-presence customization: honor the same list/tile/grid
              // visualization switch used by Recent Sessions and other tabs.
              : Obx(() => peerCardUiType.value == PeerUiType.list
                  ? ListView.builder(
                      itemCount: model.devices.length,
                      itemBuilder: (context, index) =>
                          _buildDeviceCard(context, model, index),
                    )
                  : DynamicGridView.builder(
                      gridDelegate: SliverGridDelegateWithWrapping(
                          mainAxisSpacing: 8, crossAxisSpacing: 8),
                      itemCount: model.devices.length,
                      itemBuilder: (context, index) => SizedBox(
                        width: 240,
                        height:
                            peerCardUiType.value == PeerUiType.grid ? 150 : 76,
                        child: _buildDeviceCard(context, model, index),
                      ),
                    )),
        ),
      ],
    );
  }

  Widget _buildDeviceCard(
      BuildContext context, AdminPresenceModel model, int index) {
    final d = model.devices[index];
    return _AdminPresenceDeviceCard(
      device: d,
      name: _displayName(d),
      onConnect: d.online ? () => connect(context, d.id) : null,
      onDelete: d.online ? null : () => model.deleteDevice(d.id),
      onRename: (newName) => model.renameDevice(d.id, newName),
    );
  }

  /// Admin-presence customization: the user-chosen override always wins; the
  /// initial value defaults to the hostname reported by the admin API (or, if
  /// that isn't available yet, a friendly name from a locally-known peer).
  String _displayName(AdminOnlineDevice device) {
    if (device.customName != null && device.customName!.isNotEmpty) {
      return device.customName!;
    }
    if (device.name.isNotEmpty) {
      return device.name;
    }
    final peer = _findKnownPeer(device.id);
    if (peer == null) {
      return device.id;
    }
    if (peer.alias.isNotEmpty) {
      return peer.alias;
    }
    if (peer.hostname.isNotEmpty) {
      return peer.hostname;
    }
    if (peer.username.isNotEmpty) {
      return peer.username;
    }
    return peer.id;
  }

  /// Admin-presence customization: search existing RustDesk peer caches by
  /// normalized ID so formatted IDs still resolve to hostnames/aliases.
  Peer? _findKnownPeer(String id) {
    final sources = <List<Peer>>[
      gFFI.recentPeersModel.peers,
      gFFI.favoritePeersModel.peers,
      gFFI.lanPeersModel.peers,
      gFFI.abModel.peersModel.peers,
      gFFI.groupModel.peersModel.peers,
    ];
    for (final peers in sources) {
      for (final peer in peers) {
        if (_normalizeId(peer.id) == _normalizeId(id)) {
          return peer;
        }
      }
    }
    return null;
  }

  String _normalizeId(String id) => id.replaceAll(' ', '').trim();
}

/// Admin-presence customization for this Windows client version: one device
/// row in the embedded administrator online-device pane.
class _AdminPresenceDeviceCard extends StatelessWidget {
  final AdminOnlineDevice device;
  final String name;
  final VoidCallback? onConnect;
  final VoidCallback? onDelete;
  final void Function(String newName)? onRename;

  const _AdminPresenceDeviceCard({
    required this.device,
    required this.name,
    required this.onConnect,
    required this.onDelete,
    this.onRename,
  });

  /// Admin-presence customization: lets the administrator override the
  /// displayed device name. The override is stored locally on this client
  /// only (never sent to the server) and persists until the row is deleted
  /// or renamed again.
  Future<void> _showRenameDialog(BuildContext context) async {
    final controller = TextEditingController(text: name);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(translate('Rename')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: translate('Please input')),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(translate('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(translate('OK')),
          ),
        ],
      ),
    );
    if (result != null) {
      onRename?.call(result.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final subtitleStyle =
        Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey);
    return Opacity(
      opacity: device.online ? 1.0 : 0.48,
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onConnect,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: str2color(device.id, 0x7f),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.desktop_windows, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          getOnline(8, device.online),
                          Expanded(
                            child: Text(
                              name,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          if (onRename != null)
                            InkWell(
                              onTap: () => _showRenameDialog(context),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 4),
                                child: Icon(Icons.edit, size: 14, color: Colors.grey),
                              ),
                            ),
                        ],
                      ),
                      Text(
                        device.id,
                        overflow: TextOverflow.ellipsis,
                        style: subtitleStyle,
                      ),
                      Text(
                        device.online
                            ? '${translate('Last seen')}: ${device.lastSeenSecs}s'
                            : '${translate('Offline for')}: ${_formatDuration(_offlineFor())}',
                        style: subtitleStyle,
                      ),
                    ],
                  ),
                ),
                if (onDelete != null)
                  IconButton(
                    tooltip: translate('Delete'),
                    icon: const Icon(Icons.close),
                    onPressed: onDelete,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Duration _offlineFor() {
    if (device.offlineSinceMs == 0) return Duration.zero;
    final now = DateTime.now().millisecondsSinceEpoch;
    return Duration(milliseconds: now - device.offlineSinceMs);
  }

  String _formatDuration(Duration duration) {
    if (duration.inDays > 0) {
      return '${duration.inDays}d ${duration.inHours % 24}h';
    }
    if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes % 60}m';
    }
    if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m ${duration.inSeconds % 60}s';
    }
    return '${duration.inSeconds}s';
  }
}
