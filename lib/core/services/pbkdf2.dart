// lib/core/services/pbkdf2.dart
//
// PBKDF2-HMAC-SHA256 (RFC 8018) for the offline sign-in credential (sync
// spec section 6). Pure Dart on package:crypto's HMAC.
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Iterations for a new offline credential. Each stored credential keeps its
/// own count, so changing this only affects credentials saved afterwards.
/// Measured 2026-10-20: 100 000 took ~0.7 s on the dev PC (pure-Dart HMAC),
/// so 20 000 (~0.14 s there, roughly 0.5 s on a low-end phone).
const offlineHashIterations = 20000;

List<int> pbkdf2HmacSha256(List<int> password, List<int> salt, int iterations, {int length = 32}) {
  if (iterations < 1) throw ArgumentError.value(iterations, 'iterations', 'must be at least 1');
  if (length < 1) throw ArgumentError.value(length, 'length', 'must be at least 1');
  final hmac = Hmac(sha256, password);
  final out = BytesBuilder(copy: false);
  for (var block = 1; out.length < length; block++) {
    final u1 = hmac.convert([...salt, block >> 24 & 0xff, block >> 16 & 0xff, block >> 8 & 0xff, block & 0xff]).bytes;
    final t = Uint8List.fromList(u1);
    var u = u1;
    for (var i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    out.add(t);
  }
  return out.takeBytes().sublist(0, length);
}

String toHex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

List<int> fromHex(String hex) {
  if (hex.length.isOdd) throw FormatException('Odd-length hex string.', hex);
  return [for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)];
}

/// Compares in time that depends only on the length, not on where the first
/// difference is.
bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// [pbkdf2HmacSha256] on a background isolate, so a sign-in doesn't freeze
/// the UI while hashing.
Future<List<int>> pbkdf2HmacSha256InIsolate(List<int> password, List<int> salt, int iterations, {int length = 32}) =>
    Isolate.run(() => pbkdf2HmacSha256(password, salt, iterations, length: length));
