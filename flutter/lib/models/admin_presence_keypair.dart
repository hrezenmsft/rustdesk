// Admin-presence customization (v2.0.0): per-client ed25519 keypair
// generation, DPAPI-encrypted local storage, and challenge-signing helper
// for the new key-based admin auth flow (replacing the single shared admin
// token, kept only for v1.x migration — see admin_presence_model.dart).
//
// Design notes:
// - Uses `package:cryptography`'s pure-Dart Ed25519 implementation: no new
//   Rust FFI bridge surface is introduced (this fork's existing admin
//   presence code is already pure-Dart HTTP, see admin_presence_model.dart).
// - The private key is encrypted at rest with Windows DPAPI
//   (`CryptProtectData`/`CryptUnprotectData`, current-user scope, no extra
//   entropy — matches the same protection level Windows itself uses for
//   similar per-user secrets, e.g. saved RDP credentials). This is
//   Windows-only, matching the fact that this admin client feature is
//   Windows-only per the project's scope.
// - Storage location reuses the existing local-option mechanism
//   (`bind.mainGetLocalOption`/`mainSetLocalOption`) already used for
//   [kOptionAdminPresenceDevices] etc., so no new storage subsystem is
//   introduced.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:win32/win32.dart';
import 'package:ffi/ffi.dart' as pkg_ffi;

import '../consts.dart';
import 'platform_model.dart';

final _ed25519 = Ed25519();

class AdminPresenceKeyPair {
  final String label;
  final String publicKeyB64;
  final SimpleKeyPair _keyPair;

  AdminPresenceKeyPair._(this.label, this.publicKeyB64, this._keyPair);

  /// Signs [message] (typically the UTF-8 bytes of a server-issued nonce)
  /// and returns the detached signature bytes, base64-encoded — the shape
  /// `/admin/v1/auth/verify` expects.
  Future<String> signB64(String message) async {
    final signature = await _ed25519.sign(
      utf8.encode(message),
      keyPair: _keyPair,
    );
    return base64.encode(signature.bytes);
  }

  /// A short, stable identifier for this key, matching the server's
  /// `admin_keys::fingerprint_of` exactly (first 16 bytes of sha256(pubkey),
  /// lowercase hex) so the fingerprint shown here can be directly compared
  /// against `rustdesk-utils listadminkeys` output.
  Future<String> fingerprint() => fingerprintOfPublicKeyB64(publicKeyB64);
}

/// Admin-presence customization (v2.0.0): splits a 64-byte
/// libsodium/sodiumoxide `sign::SecretKey` (as printed by the server's
/// `rustdesk-utils genadminkey`) into its 32-byte seed and 32-byte public
/// key halves. Pure/synchronous and independent of platform bindings so it
/// can be unit-tested directly (see `test/admin_presence_keypair_test.dart`).
({Uint8List seed, Uint8List publicKey}) splitSodiumSecretKey(Uint8List full) {
  if (full.length != 64) {
    throw ArgumentError(
        'Invalid admin private key: expected 64 bytes, got ${full.length}');
  }
  return (seed: full.sublist(0, 32), publicKey: full.sublist(32, 64));
}

/// Admin-presence customization (v2.0.0): derives the short fingerprint for
/// a base64-encoded raw ed25519 public key, matching the server's
/// `admin_keys::fingerprint_of` exactly (first 16 bytes of sha256(pubkey),
/// lowercase hex). Pure/async-but-platform-independent so it can be
/// unit-tested directly.
Future<String> fingerprintOfPublicKeyB64(String publicKeyB64) async {
  final digest = await Sha256().hash(base64.decode(publicKeyB64));
  return digest.bytes
      .take(16)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}

/// Admin-presence customization (v2.0.0): loads the persisted admin keypair,
/// if one has been enrolled on this machine, or `null` if none exists yet
/// (the UI should then prompt for enrollment — see the pairing-code/manual
/// key-import flow in the admin presence settings screen).
Future<AdminPresenceKeyPair?> loadAdminPresenceKeyPair() async {
  final publicKeyB64 =
      bind.mainGetLocalOption(key: kOptionAdminPresencePublicKey);
  final encPrivate =
      bind.mainGetLocalOption(key: kOptionAdminPresencePrivateKeyEnc);
  if (publicKeyB64.isEmpty || encPrivate.isEmpty) {
    return null;
  }
  final label = 'admin-presence';
  try {
    final privateKeyBytes = _dpapiUnprotect(base64.decode(encPrivate));
    final keyPair = await _ed25519.newKeyPairFromSeed(privateKeyBytes);
    return AdminPresenceKeyPair._(label, publicKeyB64, keyPair);
  } catch (e) {
    // A decrypt failure most commonly means the local option was copied to
    // a different machine/user profile, where DPAPI cannot unprotect it
    // (by design — this is the same failure mode as, e.g., moving a saved
    // RDP credential to another PC). Treat it exactly like "not enrolled"
    // rather than crashing, so the UI can offer re-enrollment.
    return null;
  }
}

/// Admin-presence customization (v2.0.0): generates a brand-new ed25519
/// keypair for this admin client and imports the caller-supplied private
/// key material — used by the "import private key from `genadminkey`"
/// enrollment flow. `privateKeyB64` is the raw 64-byte libsodium/sodiumoxide
/// `sign::SecretKey` encoding the server's `rustdesk-utils genadminkey`
/// prints (seed || public key, matching `sodiumoxide::crypto::sign`'s
/// on-the-wire secret key layout), so it can be imported byte-for-byte
/// without the user needing to separately copy a public key.
Future<AdminPresenceKeyPair> importAdminPresenceKeyPair(
    String privateKeyB64) async {
  final full = base64.decode(privateKeyB64);
  final split = splitSodiumSecretKey(full);
  final seed = split.seed;
  final publicKeyBytes = split.publicKey;
  final keyPair = await _ed25519.newKeyPairFromSeed(seed);
  final publicKeyB64 = base64.encode(publicKeyBytes);

  final encPrivate = base64.encode(_dpapiProtect(seed));
  bind.mainSetLocalOption(
      key: kOptionAdminPresencePublicKey, value: publicKeyB64);
  bind.mainSetLocalOption(
      key: kOptionAdminPresencePrivateKeyEnc, value: encPrivate);

  return AdminPresenceKeyPair._('admin-presence', publicKeyB64, keyPair);
}

/// Admin-presence customization (v2.0.0): removes any enrolled admin
/// keypair from this machine (e.g. when the user chooses to un-enroll or
/// re-enroll from scratch). Does not revoke the key server-side — the
/// administrator must also run `rustdesk-utils revokeadminkey` on the
/// server for a full revocation.
void clearAdminPresenceKeyPair() {
  bind.mainSetLocalOption(key: kOptionAdminPresencePublicKey, value: '');
  bind.mainSetLocalOption(key: kOptionAdminPresencePrivateKeyEnc, value: '');
}

/// Wraps `CryptProtectData` (current-user DPAPI scope, no extra entropy, no
/// UI prompt) to encrypt [plain] for storage.
Uint8List _dpapiProtect(Uint8List plain) {
  if (!Platform.isWindows) {
    throw UnsupportedError(
        'Admin presence key storage requires Windows DPAPI');
  }
  final inBlob = pkg_ffi.calloc<CRYPT_INTEGER_BLOB>();
  final outBlob = pkg_ffi.calloc<CRYPT_INTEGER_BLOB>();
  final dataPtr = pkg_ffi.calloc<Uint8>(plain.length);
  try {
    dataPtr.asTypedList(plain.length).setAll(0, plain);
    inBlob.ref.cbData = plain.length;
    inBlob.ref.pbData = dataPtr;

    final ok = CryptProtectData(
      inBlob,
      nullptr,
      nullptr,
      nullptr,
      nullptr,
      0,
      outBlob,
    );
    if (ok == 0) {
      throw StateError('CryptProtectData failed (GetLastError=${GetLastError()})');
    }
    final result =
        Uint8List.fromList(outBlob.ref.pbData.asTypedList(outBlob.ref.cbData));
    LocalFree(outBlob.ref.pbData.cast());
    return result;
  } finally {
    pkg_ffi.calloc.free(dataPtr);
    pkg_ffi.calloc.free(inBlob);
    pkg_ffi.calloc.free(outBlob);
  }
}

/// Wraps `CryptUnprotectData` to decrypt data previously produced by
/// [_dpapiProtect] on this same Windows user profile.
Uint8List _dpapiUnprotect(Uint8List cipher) {
  if (!Platform.isWindows) {
    throw UnsupportedError(
        'Admin presence key storage requires Windows DPAPI');
  }
  final inBlob = pkg_ffi.calloc<CRYPT_INTEGER_BLOB>();
  final outBlob = pkg_ffi.calloc<CRYPT_INTEGER_BLOB>();
  final dataPtr = pkg_ffi.calloc<Uint8>(cipher.length);
  try {
    dataPtr.asTypedList(cipher.length).setAll(0, cipher);
    inBlob.ref.cbData = cipher.length;
    inBlob.ref.pbData = dataPtr;

    final ok = CryptUnprotectData(
      inBlob,
      nullptr,
      nullptr,
      nullptr,
      nullptr,
      0,
      outBlob,
    );
    if (ok == 0) {
      throw StateError('CryptUnprotectData failed (GetLastError=${GetLastError()})');
    }
    final result =
        Uint8List.fromList(outBlob.ref.pbData.asTypedList(outBlob.ref.cbData));
    LocalFree(outBlob.ref.pbData.cast());
    return result;
  } finally {
    pkg_ffi.calloc.free(dataPtr);
    pkg_ffi.calloc.free(inBlob);
    pkg_ffi.calloc.free(outBlob);
  }
}
