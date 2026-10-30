import 'package:flutter/material.dart';

import '../apps/weather/weather_service.dart';
import 'db/database.dart';
import 'sync/sync_service.dart';

enum TempUnit { celsius, fahrenheit }

/// User preferences, persisted in the local database.
class AppSettings extends ChangeNotifier {
  AppSettings(this._db);

  final AppDatabase _db;

  ThemeMode themeMode = ThemeMode.system;
  TempUnit tempUnit = TempUnit.celsius;
  String currency = 'EUR';
  String name = '';
  String googleWeatherKey = '';

  /// off, server or client
  String syncMode = 'off';
  String syncUrl = '';
  String syncToken = '';

  Map<String, String> _raw = {};

  /// Small values other parts of the app keep (news topics, vacation days, flags).
  String? raw(String key) => _raw[key];

  /// Saves a small value. Pass [quiet] for caches nobody needs to redraw for.
  Future<void> setRaw(String key, String value, {bool quiet = false}) async {
    if (_raw[key] == value) return;
    _raw[key] = value;
    if (!quiet) notifyListeners();
    await _db.writeSetting(key, value);
  }

  Future<void> load() async {
    final s = await _db.readSettings();
    _raw = Map.of(s);
    themeMode = ThemeMode.values.asNameMap()[s['themeMode']] ?? ThemeMode.system;
    tempUnit = TempUnit.values.asNameMap()[s['tempUnit']] ?? TempUnit.celsius;
    currency = s['currency'] ?? 'EUR';
    name = s['name'] ?? '';
    googleWeatherKey = s['googleWeatherKey'] ?? '';
    WeatherService.instance.googleKey = googleWeatherKey;
    syncMode = s['syncMode'] ?? 'off';
    syncUrl = s['syncUrl'] ?? '';
    syncToken = s['syncToken'] ?? '';
  }

  Future<void> setSync({required String mode, String? url, String? token}) async {
    syncMode = mode;
    if (url != null) syncUrl = url.trim();
    if (token != null) syncToken = token.trim();
    notifyListeners();
    await _db.writeSetting('syncMode', syncMode);
    await _db.writeSetting('syncUrl', syncUrl);
    await _db.writeSetting('syncToken', syncToken);
    await SyncService.instance.configure(_db, mode: syncMode, url: syncUrl, token: syncToken);
  }

  Future<void> startSync() => SyncService.instance.configure(_db, mode: syncMode, url: syncUrl, token: syncToken);

  Future<void> setThemeMode(ThemeMode value) => _set('themeMode', value.name, () => themeMode = value);
  Future<void> setTempUnit(TempUnit value) => _set('tempUnit', value.name, () => tempUnit = value);
  Future<void> setCurrency(String value) => _set('currency', value, () => currency = value);
  Future<void> setGoogleWeatherKey(String value) => _set('googleWeatherKey', value.trim(), () {
    googleWeatherKey = value.trim();
    WeatherService.instance.googleKey = googleWeatherKey;
  });
  Future<void> setName(String value) => _set('name', value.trim(), () => name = value.trim());

  Future<void> _set(String key, String value, VoidCallback apply) async {
    apply();
    notifyListeners();
    await _db.writeSetting(key, value);
  }
}

/// Makes the database and settings reachable from any widget.
///
/// Widgets that read [HubContext.settings] in build redraw when a setting
/// changes; reading [HubContext.db] never causes a redraw.
class Hub extends InheritedNotifier<AppSettings> {
  const Hub({super.key, required this.db, required this.settings, required super.child}) : super(notifier: settings);

  final AppDatabase db;
  final AppSettings settings;

  static Hub of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<Hub>()!;
}

extension HubContext on BuildContext {
  AppDatabase get db => getInheritedWidgetOfExactType<Hub>()!.db;
  AppSettings get settings => Hub.of(this).settings;
}
