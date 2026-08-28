/// Whether a search is allowed to run, and why not when it is not.
///
/// This is the bug the user actually hit: they pasted a working Serper key,
/// saved it, and every question still reported "unavailable — add a Serper key
/// in Settings". Two separate conditions had to be true, saving a key only set
/// one of them, nothing on screen said so, and the message that came out named
/// the condition that was already satisfied.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mario/core/services/ai/web_search_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  WebSearchService withKey(String? key) =>
      WebSearchService(secure: _Secrets(key));

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('a saved key is the opt-in', () {
    test('a key and no preference at all means ready', () async {
      // The whole bug: this used to be false, because the preference defaulted
      // to off and the only thing that ever wrote it was a switch the user had
      // no reason to connect to the key they had just saved.
      expect(await withKey('serper-key').status(), WebSearchStatus.ready);
      expect(await withKey('serper-key').isEnabled, isTrue);
    });

    test('an explicit off still wins', () async {
      // Turning it off is a decision; not having decided yet is not.
      final service = withKey('serper-key');
      await service.setEnabled(false);
      expect(await service.status(), WebSearchStatus.turnedOff);
      expect(await service.isEnabled, isFalse);
    });

    test('turning it back on works', () async {
      final service = withKey('serper-key');
      await service.setEnabled(false);
      await service.setEnabled(true);
      expect(await service.status(), WebSearchStatus.ready);
    });
  });

  group('no key beats everything', () {
    test('no key is noKey, whatever the preference says', () async {
      final service = withKey(null);
      expect(await service.status(), WebSearchStatus.noKey);
      await service.setEnabled(true);
      expect(await service.status(), WebSearchStatus.noKey,
          reason: 'the switch cannot conjure a key');
    });

    test('an empty stored key counts as none', () async {
      expect(await withKey('').status(), WebSearchStatus.noKey);
    });

    test('the key is checked before the preference', () async {
      // Order matters for the message: a keyless install must be told to add a
      // key, not that the feature is switched off.
      expect(await withKey(null).status(), WebSearchStatus.noKey);
    });
  });

  group('the daily cap is its own answer', () {
    test('reports limitReached rather than a bare no', () async {
      final now = DateTime.now();
      SharedPreferences.setMockInitialValues({
        'mario.ai.webSearchCount': WebSearchService.dailyLimit,
        'mario.ai.webSearchDay': '${now.year}-${now.month}-${now.day}',
      });
      expect(await withKey('k').status(), WebSearchStatus.limitReached);
    });

    test('yesterday\'s count does not block today', () async {
      SharedPreferences.setMockInitialValues({
        'mario.ai.webSearchCount': WebSearchService.dailyLimit,
        'mario.ai.webSearchDay': '1999-1-1',
      });
      expect(await withKey('k').status(), WebSearchStatus.ready);
    });
  });

  group('each state explains itself', () {
    test('every unavailable state names its own cause', () {
      // The failure was a message that blamed the key when the key was fine,
      // so each state has to say something different and specific.
      final reasons = {
        for (final s in WebSearchStatus.values)
          if (s != WebSearchStatus.ready) s: s.reason,
      };
      expect(reasons.values.toSet(), hasLength(reasons.length),
          reason: 'two states sharing a message is how this went wrong');

      expect(WebSearchStatus.noKey.reason, contains('key'));
      expect(WebSearchStatus.turnedOff.reason, contains('switched off'));
      expect(WebSearchStatus.turnedOff.reason, isNot(contains('key')),
          reason: 'telling someone with a key to add a key was the bug');
      expect(WebSearchStatus.limitReached.reason, contains('tomorrow'));
    });

    test('ready says nothing, because nothing needs saying', () {
      expect(WebSearchStatus.ready.reason, isEmpty);
    });
  });
}

/// Secure storage holding one key, or none.
class _Secrets extends FlutterSecureStorage {
  const _Secrets(this.key);
  final String? key;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      this.key;
}
