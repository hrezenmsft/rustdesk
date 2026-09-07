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
  final int lastSeenSecs;

  AdminOnlineDevice({required this.id, required this.lastSeenSecs});

  factory AdminOnlineDevice.fromJson(Map<String, dynamic> json) {
    return AdminOnlineDevice(
      id: json['id']?.toString() ?? '',
      lastSeenSecs: json['last_seen_secs'] is int
          ? json['last_seen_secs']
          : int.tryParse(json['last_seen_secs']?.toString() ?? '') ?? 0,
    );
  }
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
  List<AdminOnlineDevice> devices = [];

  bool get isLoggedIn => _jwt != null;
  String get server => _server;

  AdminPresenceModel()
      : _server = bind.mainGetLocalOption(key: kOptionAdminPresenceServer);

  void setServer(String server) {
    _server = server.trim();
    bind.mainSetLocalOption(key: kOptionAdminPresenceServer, value: _server);
    notifyListeners();
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
      final body = decode_http_response(resp);
      if (resp.statusCode == 200) {
        final map = jsonDecode(body);
        final list = (map['devices'] as List<dynamic>?) ?? [];
        devices = list
            .map((e) => AdminOnlineDevice.fromJson(e as Map<String, dynamic>))
            .toList();
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
      error = '${translate('Failed to reach admin server')}: $e';
      return false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void logout() {
    _jwt = null;
    devices = [];
    notifyListeners();
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
