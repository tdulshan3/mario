/// SettingsState + SettingsNotifier — shared_preferences-backed user prefs.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../ui/theme.dart';

enum CanvasWidth { narrow, medium, full }

class SettingsState {
  final MarioThemeMode themeMode;
  final double fontScale;
  final CanvasWidth canvasWidth;
  final bool autoCorrectMath;
  final bool spellCheck;
  final bool holdToRecord;
  final String voiceLocale;
  final bool offlineMode;

  const SettingsState({
    this.themeMode = MarioThemeMode.system,
    this.fontScale = 1.0,
    this.canvasWidth = CanvasWidth.medium,
    this.autoCorrectMath = true,
    this.spellCheck = true,
    this.holdToRecord = false,
    this.voiceLocale = 'en_US',
    this.offlineMode = false,
  });

  SettingsState copyWith({
    MarioThemeMode? themeMode,
    double? fontScale,
    CanvasWidth? canvasWidth,
    bool? autoCorrectMath,
    bool? spellCheck,
    bool? holdToRecord,
    String? voiceLocale,
    bool? offlineMode,
  }) =>
      SettingsState(
        themeMode: themeMode ?? this.themeMode,
        fontScale: fontScale ?? this.fontScale,
        canvasWidth: canvasWidth ?? this.canvasWidth,
        autoCorrectMath: autoCorrectMath ?? this.autoCorrectMath,
        spellCheck: spellCheck ?? this.spellCheck,
        holdToRecord: holdToRecord ?? this.holdToRecord,
        voiceLocale: voiceLocale ?? this.voiceLocale,
        offlineMode: offlineMode ?? this.offlineMode,
      );
}

const _kThemeMode = 'mario.theme';
const _kFontScale = 'mario.fontScale';
const _kCanvasWidth = 'mario.canvasWidth';
const _kAutoCorrectMath = 'mario.autoCorrectMath';
const _kSpellCheck = 'mario.spellCheck';
const _kHoldToRecord = 'mario.holdToRecord';
const _kVoiceLocale = 'mario.voiceLocale';
const _kOfflineMode = 'mario.offlineMode';
const _kAnthropicKey = 'anthropic_api_key';

class SettingsNotifier extends AsyncNotifier<SettingsState> {
  static const _secure = FlutterSecureStorage();

  @override
  Future<SettingsState> build() async {
    final prefs = await SharedPreferences.getInstance();
    return SettingsState(
      themeMode: _readTheme(prefs),
      fontScale: prefs.getDouble(_kFontScale) ?? 1.0,
      canvasWidth: _readWidth(prefs),
      autoCorrectMath: prefs.getBool(_kAutoCorrectMath) ?? true,
      spellCheck: prefs.getBool(_kSpellCheck) ?? true,
      holdToRecord: prefs.getBool(_kHoldToRecord) ?? false,
      voiceLocale: prefs.getString(_kVoiceLocale) ?? 'en_US',
      offlineMode: prefs.getBool(_kOfflineMode) ?? false,
    );
  }

  Future<void> _persist(SettingsState s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeMode, s.themeMode.name);
    await prefs.setDouble(_kFontScale, s.fontScale);
    await prefs.setString(_kCanvasWidth, s.canvasWidth.name);
    await prefs.setBool(_kAutoCorrectMath, s.autoCorrectMath);
    await prefs.setBool(_kSpellCheck, s.spellCheck);
    await prefs.setBool(_kHoldToRecord, s.holdToRecord);
    await prefs.setString(_kVoiceLocale, s.voiceLocale);
    await prefs.setBool(_kOfflineMode, s.offlineMode);
  }

  Future<void> change(SettingsState Function(SettingsState) mut) async {
    final current = state.valueOrNull ?? const SettingsState();
    final next = mut(current);
    state = AsyncData(next);
    await _persist(next);
  }

  Future<String?> getApiKey() => _secure.read(key: _kAnthropicKey);

  Future<void> setApiKey(String? key) =>
      key == null || key.isEmpty
          ? _secure.delete(key: _kAnthropicKey)
          : _secure.write(key: _kAnthropicKey, value: key);

  MarioThemeMode _readTheme(SharedPreferences p) {
    final s = p.getString(_kThemeMode);
    return MarioThemeMode.values
        .firstWhere((m) => m.name == s, orElse: () => MarioThemeMode.system);
  }

  CanvasWidth _readWidth(SharedPreferences p) {
    final s = p.getString(_kCanvasWidth);
    return CanvasWidth.values
        .firstWhere((m) => m.name == s, orElse: () => CanvasWidth.medium);
  }
}

final settingsProvider =
    AsyncNotifierProvider<SettingsNotifier, SettingsState>(SettingsNotifier.new);
