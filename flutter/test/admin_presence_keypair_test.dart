// Admin-presence customization (v2.0.0): unit tests for the pure/platform-
// independent parts of the client-side ed25519 keypair handling — the
// sodiumoxide-secret-key splitting logic and the fingerprint algorithm that
// must match the server's `admin_keys::fingerprint_of` exactly. These are
// the highest-risk pieces of new code (cross-library key-format assumptions
// and hand-rolled hex encoding), so they're covered directly rather than via
// the DPAPI/`bind`-dependent flows, which require the native engine.
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as std_crypto;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/models/admin_presence_keypair.dart';

void main() {
  group('splitSodiumSecretKey', () {
    test('splits a 64-byte secret key into seed(32) + public key(32)', () {
      final full = Uint8List.fromList(List<int>.generate(64, (i) => i));
      final split = splitSodiumSecretKey(full);
      expect(split.seed, equals(full.sublist(0, 32)));
      expect(split.publicKey, equals(full.sublist(32, 64)));
    });

    test('rejects payloads that are not exactly 64 bytes', () {
      expect(() => splitSodiumSecretKey(Uint8List(63)),
          throwsA(isA<ArgumentError>()));
      expect(() => splitSodiumSecretKey(Uint8List(65)),
          throwsA(isA<ArgumentError>()));
      expect(() => splitSodiumSecretKey(Uint8List(0)),
          throwsA(isA<ArgumentError>()));
    });

    test('round-trips through a real ed25519 keypair (seed used to derive '
        'the same public key sodiumoxide would report)', () async {
      // Build a fake "sodiumoxide secret key" the same way
      // `rustdesk-utils genadminkey` does: seed(32) || public_key(32).
      final ed25519 = Ed25519();
      final keyPair = await ed25519.newKeyPair();
      final seed = await keyPair.extractPrivateKeyBytes();
      final publicKey = await keyPair.extractPublicKey();
      final full =
          Uint8List.fromList([...seed, ...publicKey.bytes]);

      final split = splitSodiumSecretKey(full);
      final rederived =
          await ed25519.newKeyPairFromSeed(split.seed);
      final rederivedPublicKey = await rederived.extractPublicKey();

      expect(split.publicKey, equals(publicKey.bytes));
      expect(rederivedPublicKey.bytes, equals(publicKey.bytes));
    });
  });

  group('fingerprintOfPublicKeyB64', () {
    test('matches sha256(pubkey) truncated to 16 bytes, lowercase hex '
        '(mirrors server admin_keys::fingerprint_of)', () async {
      final pubKeyBytes =
          Uint8List.fromList(List<int>.generate(32, (i) => 255 - i));
      final pubKeyB64 = base64.encode(pubKeyBytes);

      final expectedDigest = std_crypto.sha256.convert(pubKeyBytes).bytes;
      final expectedFingerprint = expectedDigest
          .take(16)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();

      final actual = await fingerprintOfPublicKeyB64(pubKeyB64);
      expect(actual, equals(expectedFingerprint));
      expect(actual.length, 32); // 16 bytes -> 32 hex chars
    });

    test('is deterministic for the same key', () async {
      final pubKeyBytes = Uint8List.fromList(List<int>.generate(32, (i) => i));
      final pubKeyB64 = base64.encode(pubKeyBytes);
      final a = await fingerprintOfPublicKeyB64(pubKeyB64);
      final b = await fingerprintOfPublicKeyB64(pubKeyB64);
      expect(a, equals(b));
    });

    test('differs for different keys', () async {
      final a = await fingerprintOfPublicKeyB64(
          base64.encode(Uint8List.fromList(List<int>.generate(32, (i) => i))));
      final b = await fingerprintOfPublicKeyB64(base64.encode(
          Uint8List.fromList(List<int>.generate(32, (i) => 31 - i))));
      expect(a, isNot(equals(b)));
    });
  });

  group('ed25519 sign/verify message framing', () {
    test('server-side verification framing (signature bytes ++ nonce bytes) '
        'is consistent with a detached signature produced by cryptography\'s '
        'Ed25519().sign()', () async {
      final ed25519 = Ed25519();
      final keyPair = await ed25519.newKeyPair();
      const nonce = 'deadbeefcafef00d';

      final signature =
          await ed25519.sign(utf8.encode(nonce), keyPair: keyPair);
      final publicKey = await keyPair.extractPublicKey();

      // What the client sends: base64(detached signature bytes).
      final signatureB64 = base64.encode(signature.bytes);
      expect(base64.decode(signatureB64).length, 64);

      // What the server does (see admin_auth.rs::verify): treat
      // `signature_bytes ++ nonce_bytes` as a sodiumoxide "attached
      // signature" and call sign::verify. Reproduce the equivalent check
      // using `cryptography`'s own verify to confirm the detached signature
      // itself is valid for (nonce, public_key) independent of that framing.
      final isValid = await ed25519.verify(
        utf8.encode(nonce),
        signature: Signature(base64.decode(signatureB64),
            publicKey: publicKey),
      );
      expect(isValid, isTrue);
    });
  });
}
