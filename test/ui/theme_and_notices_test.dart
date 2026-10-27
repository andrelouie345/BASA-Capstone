// test/ui/theme_and_notices_test.dart
// The colour defaults + saved changes, the hex helpers of the Colours screen,
// and how a sign-in refusal is recognised as a version refusal.
import 'package:basa_capstone/core/models/theme_settings.dart';
import 'package:basa_capstone/ui/common/version_notice.dart';
import 'package:basa_capstone/ui/theme/basa_colors.dart';
import 'package:basa_capstone/ui/theme/colours_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('basaColors', () {
    test('every name is one ThemeSettings accepts, and names are unique', () {
      final names = basaColors.map((c) => c.name).toList();
      expect(names.toSet().length, names.length);
      for (final c in basaColors) {
        expect(ThemeSettings.isValidColorName(c.name), isTrue, reason: c.name);
        expect(ThemeSettings.isValidArgb(c.light), isTrue);
        expect(ThemeSettings.isValidArgb(c.dark), isTrue);
      }
    });

    test('a saved change wins over the default; the rest stay default', () {
      final scheme = basaColorScheme(Brightness.light, {'primary': 0xFF112233});
      expect(scheme.primary.toARGB32(), 0xFF112233);
      expect(scheme.surface.toARGB32(), basaDefaultColor(Brightness.light, 'surface'));
      expect(scheme.brightness, Brightness.light);
    });

    test('dark mode uses the dark defaults', () {
      final scheme = basaColorScheme(Brightness.dark, const {});
      expect(scheme.primary.toARGB32(), basaDefaultColor(Brightness.dark, 'primary'));
      expect(scheme.brightness, Brightness.dark);
    });
  });

  group('hex', () {
    test('round trip', () {
      expect(hexOf(0xFF1F4E8C), '#1F4E8C');
      expect(hexOf(0x801F4E8C), '#801F4E8C');
      expect(parseHex('#1f4e8c'), 0xFF1F4E8C);
      expect(parseHex('801F4E8C'), 0x801F4E8C);
      expect(parseHex('#12345'), isNull);
      expect(parseHex('zzzzzz'), isNull);
    });
  });

  group('versionRefusalKind', () {
    test('reads who must update', () {
      expect(versionRefusalKind('Sign-in refused: this BASA app is too old for the database.\nUpdate BASA'),
          VersionRefusalKind.updateApp);
      expect(versionRefusalKind('Sign-in refused: the database is older than this BASA app.\n  x.sql'),
          VersionRefusalKind.updateServer);
      expect(versionRefusalKind("Sign-in refused: couldn't check the database version (e). Try again."),
          VersionRefusalKind.checkFailed);
    });

    test('other refusals are not version refusals', () {
      expect(versionRefusalKind('Sign-in failed: account is inactive'), isNull);
      expect(versionRefusalKind('cloud.url not set.'), isNull);
    });
  });
}
