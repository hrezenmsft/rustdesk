import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../consts.dart';
import '../common.dart';
import '../utils/http_service.dart' as http;
import 'platform_model.dart';

/// A single device reported as currently online by the admin presence API.
/// Intentionally carries no IP/address data (least-privilege client model).
class AdminOnlineDevice {
  final String id;
  final String name;
  final int lastSeenSecs;
  final bool online;
  final int lastSeenAtMs;
  final int offlineSinceMs;

  AdminOnlineDevice({
    required this.id,
    required this.name,
    required this.lastSeenSecs,
    required this.online,
    required this.lastSeenAtMs,
    required this.offlineSinceMs,
  });

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
    );
  }

  AdminOnlineDevice copyWith({
    String? name,
    int? lastSeenSecs,
    bool? online,
    int? lastSeenAtMs,
    int? offlineSinceMs,
  }) {
    return AdminOnlineDevice(
      id: id,
      name: name ?? this.name,
      lastSeenSecs: lastSeenSecs ?? this.lastSeenSecs,
      online: online ?? this.online,
      lastSeenAtMs: lastSeenAtMs ?? this.lastSeenAtMs,
      offlineSinceMs: offlineSinceMs ?? this.offlineSinceMs,
    );
  }

  Map<String, dynamic> toCacheJson() => {
        'id': id,
        'name': name,
        'last_seen_secs': lastSeenSecs,
        'online': online,
        'last_seen_at_ms': lastSeenAtMs,
        'offline_since_ms': offlineSinceMs,
      };
}

/// Client for the custom admin presence API (`/admin/v1/...`).
///
/// The admin server address (host:port) is persisted locally via
/// [kOptionAdminPresenceServer] (non-secret). The admin token and the JWT
/// issued after login are held in memory only for the lifetime of the app
/// session and are never written to disk.
class AdminPresenceModel with ChangeNotifier {
  String _server;
  String? _jwt;
  bool loading = false;
  String? error;
  bool serverOnline = false;
  List<AdminOnlineDevice> devices = [];

  bool get isLoggedIn => _jwt != null;
  String get server => _server;
  bool get hasSavedConfig =>
      bind.mainGetLocalOption(key: kOptionAdminPresenceServer).isNotEmpty &&
      bind.mainGetLocalOption(key: kOptionAdminPresenceToken).isNotEmpty;

  AdminPresenceModel()
      : _server = bind.mainGetLocalOption(key: kOptionAdminPresenceServer) {
    devices = _loadCachedDevices();
  }

  void setServer(String server) {
    _server = server.trim();
    bind.mainSetLocalOption(key: kOptionAdminPresenceServer, value: _server);
    notifyListeners();
  }

  static String savedToken() =>
      bind.mainGetLocalOption(key: kOptionAdminPresenceToken);

  Future<bool> loginWithSavedToken() async {
    _server = bind.mainGetLocalOption(key: kOptionAdminPresenceServer);
    final token = savedToken();
    if (_server.isEmpty || token.isEmpty) {
      error = translate('Configure admin presence in Settings > Network');
      notifyListeners();
      return false;
    }
    return login(token);
  }

  String _baseUrl() {
    final s = _server.trim();
    if (s.isEmpty) return '';
    if (s.startsWith('http://') || s.startsWith('https://')) return s;
    return 'http://$s';
  }

  /// Logs into the admin API with the given shared admin token.
  /// The token itself is never persisted; only the resulting short-lived
  /// JWT is kept in memory.
  Future<bool> login(String token) async {
    if (_baseUrl().isEmpty) {
      error = translate('Please input a valid admin server address');
      notifyListeners();
      return false;
    }
    loading = true;
    error = null;
    notifyListeners();
    try {
      final uri = Uri.parse('${_baseUrl()}/admin/v1/auth/login');
      final resp = await http.post(uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'token': token}));
      serverOnline = true;
      final body = decode_http_response(resp);
      if (resp.statusCode == 200) {
        final map = jsonDecode(body);
        final jwt = map['access_token']?.toString();
        if (jwt == null || jwt.isEmpty) {
          error = translate('Invalid response from admin server');
          return false;
        }
        _jwt = jwt;
        return true;
      } else {
        error = _extractError(body) ??
            '${translate('Login failed with status')} ${resp.statusCode}';
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

  /// Fetches the current list of online devices. Requires a prior
  /// successful [login]; on 401 the caller should re-prompt for login.
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
      final resp = await http
          .get(uri, headers: {'Authorization': 'Bearer $_jwt'});
      serverOnline = true;
      final body = decode_http_response(resp);
      if (resp.statusCode == 200) {
        final map = jsonDecode(body);
        final list = (map['devices'] as List<dynamic>?) ?? [];
        final myId = await bind.mainGetMyId();
        final onlineDevices = list
            .map((e) => AdminOnlineDevice.fromJson(e as Map<String, dynamic>))
            .where((d) => d.id != myId)
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
    devices = devices.where((d) => d.id != id).toList();
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
      ..sort((a, b) {
        if (a.online != b.online) return a.online ? -1 : 1;
        final an = a.name.isEmpty ? a.id : a.name;
        final bn = b.name.isEmpty ? b.id : b.name;
        return an.toLowerCase().compareTo(bn.toLowerCase());
      });
    _saveCachedDevices();
  }

  List<AdminOnlineDevice> _loadCachedDevices() {
    try {
      final raw = bind.mainGetLocalOption(key: kOptionAdminPresenceDevices);
      if (raw.isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => AdminOnlineDevice.fromJson(e as Map<String, dynamic>))
          .toList();
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
