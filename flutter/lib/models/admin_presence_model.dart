import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../consts.dart';
import '../common.dart';
import '../utils/http_service.dart' as http;
import 'admin_presence_keypair.dart';
import 'platform_model.dart';

/// Admin-presence customization for this Windows client version: a single
/// device reported as currently online by the self-hosted admin presence API.
/// Intentionally carries no IP/address data (least-privilege client model).
class AdminOnlineDevice {
  final String id;
  final String name;
  final int lastSeenSecs;
  final bool online;
  final int lastSeenAtMs;
  final int offlineSinceMs;
  // Admin-presence customization: user-assigned display name override. Starts
  // unset (falls back to the reported hostname in [name]) and, once set,
  // persists across refreshes until the administrator deletes the device row.
  final String? customName;

  AdminOnlineDevice({
    required this.id,
    required this.name,
    required this.lastSeenSecs,
    required this.online,
    required this.lastSeenAtMs,
    required this.offlineSinceMs,
    this.customName,
  });

  /// Admin-presence customization: name shown in the UI — the user-chosen
  /// override if set, otherwise the hostname reported by the admin API.
  String get displayName =>
      (customName != null && customName!.isNotEmpty) ? customName! : name;

  factory AdminOnlineDevice.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final seenSecs =
        double.tryParse(json['last_seen_secs']?.toString() ?? '') ?? 0;
    return AdminOnlineDevice(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      lastSeenSecs: seenSecs.round(),
      online: json['online'] is bool ? json['online'] : true,
      lastSeenAtMs:
          json['last_seen_at_ms'] is int ? json['last_seen_at_ms'] : now,
      offlineSinceMs: json['offline_since_ms'] is int
          ? json['offline_since_ms']
          : 0,
      customName: json['custom_name']?.toString(),
    );
  }

  AdminOnlineDevice copyWith({
    String? name,
    int? lastSeenSecs,
    bool? online,
    int? lastSeenAtMs,
    int? offlineSinceMs,
    String? customName,
    bool clearCustomName = false,
  }) {
    return AdminOnlineDevice(
      id: id,
      name: name ?? this.name,
      lastSeenSecs: lastSeenSecs ?? this.lastSeenSecs,
      online: online ?? this.online,
      lastSeenAtMs: lastSeenAtMs ?? this.lastSeenAtMs,
      offlineSinceMs: offlineSinceMs ?? this.offlineSinceMs,
      customName:
          clearCustomName ? null : (customName ?? this.customName),
    );
  }

  Map<String, dynamic> toCacheJson() => {
        'id': id,
        'name': name,
        'last_seen_secs': lastSeenSecs,
        'online': online,
        'last_seen_at_ms': lastSeenAtMs,
        'offline_since_ms': offlineSinceMs,
        if (customName != null && customName!.isNotEmpty)
          'custom_name': customName,
      };
}

/// Admin-presence customization (v2.0.0): fixed TCP port the admin API
/// listens on. As of v2.0.0 the client no longer lets the user configure a
/// separate admin-presence server address/port: it reuses the same host
/// already configured for the ID/rendezvous server (option
/// `custom-rendezvous-server`) and always targets this port.
const int kAdminPresenceApiPort = 21114;

/// Admin-presence customization for this Windows client version: client for
/// the custom admin presence API (`/admin/v1/...`).
///
/// As of v2.0.0 the admin API host is derived from the ID/rendezvous server
/// address (option `custom-rendezvous-server`, configured in Settings >
/// Network) with the fixed [kAdminPresenceApiPort] admin port — there is no
/// separate admin-presence server address setting anymore. The server-issued
/// JWT is kept only in memory for the lifetime of the app session.
class AdminPresenceModel with ChangeNotifier {
  String? _jwt;
  bool loading = false;
  String? error;
  bool serverOnline = false;
  List<AdminOnlineDevice> devices = [];

  bool get isLoggedIn => _jwt != null;

  /// Admin-presence customization (v2.0.0): the host the admin API will be
  /// reached at, i.e. the configured ID/rendezvous server with any port
  /// suffix stripped. Empty if the ID server isn't configured yet.
  String get serverHost => _idServerHost();

  /// Admin-presence customization (v2.0.0): the full admin API base address
  /// (host:port) that will be used, for display purposes in Settings.
  String get server =>
      serverHost.isEmpty ? '' : '$serverHost:$kAdminPresenceApiPort';

  /// Admin-presence customization (v2.0.0): true once the ID/rendezvous
  /// server address is configured and a per-client ed25519 keypair has been
  /// enrolled on this machine — the two prerequisites to auto-login.
  bool get hasSavedConfig =>
      serverHost.isNotEmpty &&
      bind.mainGetLocalOption(key: kOptionAdminPresencePublicKey).isNotEmpty;

  /// Admin-presence customization (v2.0.0): true once a per-client ed25519
  /// keypair has been enrolled on this machine (see
  /// `admin_presence_keypair.dart`). This is the only supported auth method
  /// as of v2.0.0 — the legacy shared-token login has been removed and
  /// v2.0.0 clients are not compatible with pre-2.0.0 servers.
  bool get hasEnrolledKey =>
      bind.mainGetLocalOption(key: kOptionAdminPresencePublicKey).isNotEmpty;

  /// Admin-presence customization: whether the device list should
  /// auto-refresh periodically. Persisted locally; defaults to enabled.
  bool get autoRefresh {
    final v = bind.mainGetLocalOption(key: kOptionAdminPresenceAutoRefresh);
    return v.isEmpty || v == 'Y';
  }

  set autoRefresh(bool value) {
    bind.mainSetLocalOption(
      key: kOptionAdminPresenceAutoRefresh,
      value: value ? 'Y' : 'N',
    );
    notifyListeners();
  }

  AdminPresenceModel() {
    devices = _loadCachedDevices();
  }

  /// Admin-presence customization (v2.0.0): reads the configured
  /// ID/rendezvous server address and strips any `:port` suffix, since the
  /// admin API always uses [kAdminPresenceApiPort] regardless of the ID
  /// server's own (rendezvous) port.
  String _idServerHost() {
    final raw =
        bind.mainGetOptionSync(key: 'custom-rendezvous-server').trim();
    if (raw.isEmpty) return '';
    var host = raw;
    if (host.startsWith('http://')) host = host.substring('http://'.length);
    if (host.startsWith('https://')) host = host.substring('https://'.length);
    final colonIdx = host.lastIndexOf(':');
    if (colonIdx > 0 && !host.contains(']', colonIdx)) {
      final maybePort = host.substring(colonIdx + 1);
      if (int.tryParse(maybePort) != null) {
        host = host.substring(0, colonIdx);
      }
    }
    return host;
  }

  /// Admin-presence customization (v2.0.0): imports a private key produced
  /// by `rustdesk-utils genadminkey` and returns its fingerprint on success,
  /// or throws with a user-facing message on failure. Used by the settings
  /// dialog's enrollment flow.
  static Future<String> enrollKey(String privateKeyB64) async {
    final keyPair = await importAdminPresenceKeyPair(privateKeyB64.trim());
    return keyPair.fingerprint();
  }

  /// Admin-presence customization (v2.0.0): fingerprint of the currently
  /// enrolled key, or `null` if none is enrolled / it fails to load (e.g.
  /// DPAPI data from a different machine/user).
  static Future<String?> enrolledKeyFingerprint() async {
    final keyPair = await loadAdminPresenceKeyPair();
    return keyPair?.fingerprint();
  }

  /// Admin-presence customization (v2.0.0): removes the enrolled keypair
  /// from this machine only (does not revoke it server-side).
  static void unenrollKey() => clearAdminPresenceKeyPair();

  /// Admin-presence customization (v2.0.0): logs in using the enrolled
  /// ed25519 keypair. The legacy shared admin token login has been removed
  /// in v2.0.0 — this client is only compatible with v2.0.0+ servers.
  Future<bool> autoLogin() async {
    if (serverHost.isEmpty) {
      error = translate('Configure admin presence in Settings > Network');
      notifyListeners();
      return false;
    }
    if (!hasEnrolledKey) {
      error = translate('Configure admin presence in Settings > Network');
      notifyListeners();
      return false;
    }
    return loginWithKeyPair();
  }

  /// Admin-presence customization (v2.0.0): primary login path — performs
  /// the ed25519 challenge/verify handshake using the keypair enrolled via
  /// `rustdesk-utils genadminkey` (see `admin_presence_keypair.dart`).
  Future<bool> loginWithKeyPair() async {
    if (_baseUrl().isEmpty) {
      error = translate('Please input a valid admin server address');
      notifyListeners();
      return false;
    }
    loading = true;
    error = null;
    notifyListeners();
    try {
      final keyPair = await loadAdminPresenceKeyPair();
      if (keyPair == null) {
        error = translate(
            'No admin key enrolled on this device. Import a key generated with rustdesk-utils genadminkey.');
        return false;
      }
      final challengeUri = Uri.parse('${_baseUrl()}/admin/v1/auth/challenge');
      final challengeResp = await http.post(challengeUri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'public_key': keyPair.publicKeyB64}));
      serverOnline = true;
      final challengeBody = decode_http_response(challengeResp);
      if (challengeResp.statusCode != 200) {
        error = _extractError(challengeBody) ??
            '${translate('Login failed with status')} ${challengeResp.statusCode}';
        return false;
      }
      final nonce = jsonDecode(challengeBody)['nonce']?.toString();
      if (nonce == null || nonce.isEmpty) {
        error = translate('Invalid response from admin server');
        return false;
      }
      final signature = await keyPair.signB64(nonce);
      final verifyUri = Uri.parse('${_baseUrl()}/admin/v1/auth/verify');
      final verifyResp = await http.post(verifyUri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'public_key': keyPair.publicKeyB64,
            'nonce': nonce,
            'signature': signature,
          }));
      final verifyBody = decode_http_response(verifyResp);
      if (verifyResp.statusCode == 200) {
        final map = jsonDecode(verifyBody);
        final jwt = map['access_token']?.toString();
        if (jwt == null || jwt.isEmpty) {
          error = translate('Invalid response from admin server');
          return false;
        }
        _jwt = jwt;
        return true;
      } else {
        error = _extractError(verifyBody) ??
            '${translate('Login failed with status')} ${verifyResp.statusCode}';
        return false;
      }
    } catch (e) {
      serverOnline = false;
      error = '${translate('Failed to reach admin server')}: $e';
      return false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  String _baseUrl() {
    final host = serverHost;
    if (host.isEmpty) return '';
    return 'http://$host:$kAdminPresenceApiPort';
  }

  /// Admin-presence customization: fetches the current online-device list.
  /// Requires a prior successful [login]; on 401 the caller should re-login.
  Future<bool> refreshDevices() async {
    if (_jwt == null) {
      error = translate('Not logged in');
      notifyListeners();
      return false;
    }
    loading = true;
    error = null;
    notifyListeners();
    try {
      final uri =
          Uri.parse('${_baseUrl()}/admin/v1/devices?status=online');
      final jwt = _jwt!;
      final headers = <String, String>{'Authorization': 'Bearer $jwt'};
      final resp = await http
          .get(uri, headers: headers);
      serverOnline = true;
      final body = decode_http_response(resp);
      if (resp.statusCode == 200) {
        final map = jsonDecode(body);
        final list = (map['devices'] as List<dynamic>?) ?? [];
        final myId = _normalizeId(await bind.mainGetMyId());
        devices = devices.where((d) => _normalizeId(d.id) != myId).toList();
        final onlineDevices = list
            .map((e) => AdminOnlineDevice.fromJson(e as Map<String, dynamic>))
            .where((d) => _normalizeId(d.id) != myId)
            .toList();
        _mergeOnlineDevices(onlineDevices);
        return true;
      } else if (resp.statusCode == 401) {
        _jwt = null;
        error = translate('Session expired, please login again');
        return false;
      } else {
        error = _extractError(body) ??
            '${translate('Failed with status')} ${resp.statusCode}';
        return false;
      }
    } catch (e) {
      serverOnline = false;
      error = '${translate('Failed to reach admin server')}: $e';
      return false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void logout() {
    _jwt = null;
    notifyListeners();
  }

  void deleteDevice(String id) {
    final normalized = _normalizeId(id);
    devices = devices.where((d) => _normalizeId(d.id) != normalized).toList();
    _saveCachedDevices();
    notifyListeners();
  }

  /// Admin-presence customization: sets (or clears, when [name] is empty) the
  /// user-chosen display-name override for a device. The override persists
  /// across refreshes/reconnects and survives the underlying hostname
  /// changing, until the administrator removes the device row entirely.
  void renameDevice(String id, String name) {
    final normalized = _normalizeId(id);
    devices = devices
        .map((d) => _normalizeId(d.id) == normalized
            ? d.copyWith(
                customName: name.trim(), clearCustomName: name.trim().isEmpty)
            : d)
        .toList();
    _saveCachedDevices();
    notifyListeners();
  }

  void _mergeOnlineDevices(List<AdminOnlineDevice> onlineDevices) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final merged = <String, AdminOnlineDevice>{
      for (final d in devices) d.id: d,
    };
    final onlineIds = <String>{};
    for (final online in onlineDevices) {
      onlineIds.add(online.id);
      final existing = merged[online.id];
      merged[online.id] = online.copyWith(
        name: online.name.isNotEmpty ? online.name : existing?.name,
        online: true,
        lastSeenAtMs: now - (online.lastSeenSecs * 1000),
        offlineSinceMs: 0,
        // Preserve the administrator's chosen display-name override across
        // refreshes; it's only cleared when the device row is deleted.
        customName: existing?.customName,
      );
    }
    for (final entry in merged.entries.toList()) {
      if (onlineIds.contains(entry.key)) continue;
      final d = entry.value;
      merged[entry.key] = d.copyWith(
        online: false,
        offlineSinceMs: d.offlineSinceMs == 0 ? now : d.offlineSinceMs,
      );
    }
    devices = merged.values.toList()
      ..sort(_compareDevices);
    _saveCachedDevices();
  }

  /// Admin-presence customization: sort online devices first, then
  /// alphabetically by display name (falls back to ID when no name is known).
  int _compareDevices(AdminOnlineDevice a, AdminOnlineDevice b) {
    if (a.online != b.online) return a.online ? -1 : 1;
    final an = a.displayName.isEmpty ? a.id : a.displayName;
    final bn = b.displayName.isEmpty ? b.id : b.displayName;
    return an.toLowerCase().compareTo(bn.toLowerCase());
  }

  /// Admin-presence customization: cached devices preserve stale/offline rows
  /// between refreshes so administrators can see and delete old entries.
  List<AdminOnlineDevice> _loadCachedDevices() {
    try {
      final raw = bind.mainGetLocalOption(key: kOptionAdminPresenceDevices);
      if (raw.isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      final loaded = list
          .map((e) => AdminOnlineDevice.fromJson(e as Map<String, dynamic>))
          .toList();
      loaded.sort(_compareDevices);
      return loaded;
    } catch (e) {
      debugPrint('Failed to load cached admin presence devices: $e');
      return [];
    }
  }

  void _saveCachedDevices() {
    bind.mainSetLocalOption(
      key: kOptionAdminPresenceDevices,
      value: jsonEncode(devices.map((d) => d.toCacheJson()).toList()),
    );
  }

  /// Admin-presence customization: normalize RustDesk IDs before comparing
  /// because the UI may display grouped IDs such as `1 262 916 439`.
  String _normalizeId(String id) => id.replaceAll(' ', '').trim();

  String? _extractError(String body) {
    try {
      final map = jsonDecode(body);
      final e = map['error'];
      return e?.toString();
    } catch (_) {
      return null;
    }
  }
}
