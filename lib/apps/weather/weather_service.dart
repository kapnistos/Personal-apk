import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/format.dart';

/// Weather data from Open-Meteo (free, no API key).
class Forecast {
  Forecast({
    required this.temperature,
    required this.feelsLike,
    required this.humidity,
    required this.wind,
    required this.code,
    required this.isDay,
    required this.hours,
    required this.days,
    required this.fetchedAt,
  });

  final double temperature;
  final double feelsLike;
  final int humidity;
  final double wind;
  final int code;
  final bool isDay;
  final List<HourForecast> hours;
  final List<DayForecast> days;
  final DateTime fetchedAt;
  String source = '';
  String? note;

  factory Forecast.fromJson(Map<String, dynamic> j) {
    final c = j['current'] as Map<String, dynamic>;
    final h = j['hourly'] as Map<String, dynamic>;
    final d = j['daily'] as Map<String, dynamic>;
    final now = DateTime.parse(c['time'] as String);

    final hours = <HourForecast>[];
    final hTimes = (h['time'] as List).cast<String>();
    for (var i = 0; i < hTimes.length; i++) {
      final t = DateTime.parse(hTimes[i]);
      if (t.isBefore(now.subtract(const Duration(minutes: 59)))) continue;
      hours.add(HourForecast(
        time: t,
        temperature: _num(h['temperature_2m'][i]),
        code: (h['weather_code'][i] as num?)?.toInt() ?? 0,
        rainChance: (h['precipitation_probability'][i] as num?)?.toInt() ?? 0,
      ));
      if (hours.length == 24) break;
    }

    final days = <DayForecast>[];
    final dTimes = (d['time'] as List).cast<String>();
    for (var i = 0; i < dTimes.length; i++) {
      days.add(DayForecast(
        date: DateTime.parse(dTimes[i]),
        max: _num(d['temperature_2m_max'][i]),
        min: _num(d['temperature_2m_min'][i]),
        code: (d['weather_code'][i] as num?)?.toInt() ?? 0,
        rainChance: (d['precipitation_probability_max'][i] as num?)?.toInt() ?? 0,
        sunrise: DateTime.parse(d['sunrise'][i] as String),
        sunset: DateTime.parse(d['sunset'][i] as String),
      ));
    }

    return Forecast(
      temperature: _num(c['temperature_2m']),
      feelsLike: _num(c['apparent_temperature']),
      humidity: (c['relative_humidity_2m'] as num?)?.toInt() ?? 0,
      wind: _num(c['wind_speed_10m']),
      code: (c['weather_code'] as num?)?.toInt() ?? 0,
      isDay: (c['is_day'] as num?) == 1,
      hours: hours,
      days: days,
      fetchedAt: DateTime.now(),
    );
  }

  static double _num(Object? v) => (v as num?)?.toDouble() ?? 0;
}

class HourForecast {
  HourForecast({required this.time, required this.temperature, required this.code, required this.rainChance});
  final DateTime time;
  final double temperature;
  final int code;
  final int rainChance;
}

class DayForecast {
  DayForecast({
    required this.date,
    required this.max,
    required this.min,
    required this.code,
    required this.rainChance,
    required this.sunrise,
    required this.sunset,
  });
  final DateTime date;
  final double max;
  final double min;
  final int code;
  final int rainChance;
  final DateTime sunrise;
  final DateTime sunset;
}

class Place {
  Place({required this.name, required this.region, required this.latitude, required this.longitude});
  final String name;
  final String region;
  final double latitude;
  final double longitude;
}

class WeatherException implements Exception {
  WeatherException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// One point of the short-term rain forecast.
class RainPoint {
  RainPoint(this.time, this.mmPerHour);
  final DateTime time;
  final double mmPerHour;
}

class Nowcast {
  Nowcast({required this.points, required this.source});
  final List<RainPoint> points;
  final String source;

  bool get dry => points.every((p) => p.mmPerHour < 0.1);

  /// A one-line summary, e.g. "Rain starting around 14:35".
  String summary(String Function(DateTime) fmt) {
    if (points.isEmpty) return 'No short-term data';
    final wetNow = points.first.mmPerHour >= 0.1;
    if (dry) return 'No rain expected in the next ${_hours()} hours';
    if (wetNow) {
      final stop = points.firstWhere((p) => p.mmPerHour < 0.1, orElse: () => points.last);
      return stop == points.last && stop.mmPerHour >= 0.1
          ? 'Rain for the next ${_hours()} hours'
          : 'Rain stopping around ${fmt(stop.time)}';
    }
    final start = points.firstWhere((p) => p.mmPerHour >= 0.1);
    return 'Rain starting around ${fmt(start.time)}';
  }

  int _hours() => ((points.last.time.difference(points.first.time).inMinutes + 5) / 60).round();
}

enum WeatherProvider { openMeteo, google }

class WeatherService {
  WeatherService({http.Client? client}) : _client = client ?? http.Client();

  static final instance = WeatherService();

  final http.Client _client;
  final _cache = <String, Forecast>{};
  final _nowcastCache = <String, (DateTime, Nowcast)>{};

  /// Google Maps Platform key. When set, Google Weather is used for the forecast.
  String googleKey = '';

  WeatherProvider get provider => googleKey.isEmpty ? WeatherProvider.openMeteo : WeatherProvider.google;

  /// Puts data in the caches. Used by the screenshot harness.
  void seed(double lat, double lon, Forecast f, Nowcast n) {
    _cache[_key(lat, lon)] = f;
    _nowcastCache[_key(lat, lon)] = (DateTime.now(), n);
  }

  /// Returns a cached forecast if it is under 15 minutes old.
  Forecast? cached(double lat, double lon) {
    final f = _cache[_key(lat, lon)];
    if (f == null || DateTime.now().difference(f.fetchedAt).inMinutes >= 15) return null;
    return f;
  }

  Future<Forecast> forecast(double lat, double lon, {bool force = false}) async {
    if (!force) {
      final c = cached(lat, lon);
      if (c != null) return c;
    }
    Forecast f;
    if (provider == WeatherProvider.google) {
      try {
        f = await GoogleWeather(_client, googleKey).forecast(lat, lon);
      } on WeatherException {
        // Fall back so a bad key or quota never leaves the screen empty.
        f = await _openMeteo(lat, lon);
        f.note = 'Google Weather failed, showing Open-Meteo';
      }
    } else {
      f = await _openMeteo(lat, lon);
    }
    _cache[_key(lat, lon)] = f;
    return f;
  }

  Future<Forecast> _openMeteo(double lat, double lon) async {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': '$lat',
      'longitude': '$lon',
      'current': 'temperature_2m,apparent_temperature,relative_humidity_2m,is_day,weather_code,wind_speed_10m',
      'hourly': 'temperature_2m,weather_code,precipitation_probability',
      'daily': 'weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset',
      'timezone': 'auto',
      'forecast_days': '10',
    });
    final f = Forecast.fromJson(await _getJson(uri));
    f.source = 'Open-Meteo';
    return f;
  }

  /// Rain for the next 4 hours. Uses Buienradar radar (5-minute steps, about
  /// 2 hours) inside its coverage area, and Open-Meteo 15-minute data for the
  /// rest of the window or anywhere else.
  Future<Nowcast> nowcast(double lat, double lon, {bool force = false}) async {
    final key = _key(lat, lon);
    final hit = _nowcastCache[key];
    if (!force && hit != null && DateTime.now().difference(hit.$1).inMinutes < 5) return hit.$2;

    final results = await Future.wait([
      if (Buienradar.covers(lat, lon)) Buienradar(_client).rain(lat, lon).catchError((_) => <RainPoint>[]),
      _openMeteoMinutely(lat, lon).catchError((_) => <RainPoint>[]),
    ]);
    final radar = results.length == 2 ? results.first : <RainPoint>[];
    final model = results.last;
    if (radar.isEmpty && model.isEmpty) {
      throw WeatherException('Short-term rain forecast unavailable.');
    }
    final points = [...radar];
    final radarEnd = radar.isEmpty ? null : radar.last.time;
    points.addAll(model.where((p) => radarEnd == null || p.time.isAfter(radarEnd)));
    final n = Nowcast(
      points: points,
      source: radar.isEmpty ? 'Open-Meteo' : 'Buienradar + Open-Meteo',
    );
    _nowcastCache[key] = (DateTime.now(), n);
    return n;
  }

  Future<List<RainPoint>> _openMeteoMinutely(double lat, double lon) async {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': '$lat',
      'longitude': '$lon',
      'minutely_15': 'precipitation',
      'forecast_minutely_15': '17',
      'past_minutely_15': '1',
      'timezone': 'auto',
    });
    final j = await _getJson(uri);
    final m = j['minutely_15'] as Map<String, dynamic>;
    final times = (m['time'] as List).cast<String>();
    final values = m['precipitation'] as List;
    return [
      for (var i = 0; i < times.length; i++)
        // precipitation is mm per 15 minutes; convert to mm/h.
        RainPoint(DateTime.parse(times[i]), ((values[i] as num?)?.toDouble() ?? 0) * 4),
    ];
  }

  void clearCache() => _cache.clear();

  /// The town at a position, from BigDataCloud's free lookup (no key). Null if unknown.
  Future<String?> placeName(double lat, double lon) async {
    try {
      final j = await _getJson(Uri.https('api.bigdatacloud.net', '/data/reverse-geocode-client', {
        'latitude': '$lat',
        'longitude': '$lon',
        'localityLanguage': 'en',
      }));
      final name = [j['city'], j['locality']].whereType<String>().where((s) => s.isNotEmpty).firstOrNull;
      return name;
    } catch (_) {
      return null;
    }
  }

  Future<List<Place>> search(String name) async {
    if (name.trim().length < 2) return [];
    final uri = Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
      'name': name.trim(),
      'count': '8',
      'language': 'en',
      'format': 'json',
    });
    final json = await _getJson(uri);
    final results = (json['results'] as List?) ?? [];
    return results.map((r) {
      final m = r as Map<String, dynamic>;
      final region = [m['admin1'], m['country']].whereType<String>().where((s) => s.isNotEmpty).join(', ');
      return Place(
        name: m['name'] as String,
        region: region,
        latitude: (m['latitude'] as num).toDouble(),
        longitude: (m['longitude'] as num).toDouble(),
      );
    }).toList();
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async =>
      jsonDecode(await fetchText(_client, uri)) as Map<String, dynamic>;

  String _key(double lat, double lon) => '${lat.toStringAsFixed(3)},${lon.toStringAsFixed(3)}';
}

Future<String> fetchText(http.Client client, Uri uri) async {
  try {
    final res = await client.get(uri).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) {
      throw WeatherException('Weather service answered ${res.statusCode}.');
    }
    return res.body;
  } on WeatherException {
    rethrow;
  } catch (_) {
    throw WeatherException('Could not reach the weather service. Check your connection.');
  }
}

/// Buienradar precipitation radar forecast for the Netherlands and Belgium.
class Buienradar {
  Buienradar(this._client);
  final http.Client _client;

  /// Rough bounding box of the radar coverage.
  static bool covers(double lat, double lon) => lat >= 49.3 && lat <= 54.0 && lon >= 1.8 && lon <= 8.0;

  Future<List<RainPoint>> rain(double lat, double lon, {DateTime? now}) async {
    final uri = Uri.https('gadgets.buienradar.nl', '/data/raintext/', {
      'lat': lat.toStringAsFixed(2),
      'lon': lon.toStringAsFixed(2),
    });
    return parse(await fetchText(_client, uri), now: now ?? DateTime.now());
  }

  /// Lines look like "077|14:35": intensity 0-255, then local time.
  /// mm/h = 10 ^ ((intensity - 109) / 32).
  static List<RainPoint> parse(String body, {required DateTime now}) {
    final out = <RainPoint>[];
    var day = DateTime(now.year, now.month, now.day);
    int? lastMinutes;
    for (final line in body.split(RegExp(r'\r?\n'))) {
      final parts = line.trim().split('|');
      if (parts.length != 2) continue;
      final value = int.tryParse(parts[0]);
      final hm = parts[1].split(':');
      if (value == null || hm.length != 2) continue;
      final minutes = (int.tryParse(hm[0]) ?? 0) * 60 + (int.tryParse(hm[1]) ?? 0);
      if (lastMinutes != null && minutes < lastMinutes) day = addDays(day, 1);
      lastMinutes = minutes;
      final mm = value == 0 ? 0.0 : math.pow(10, (value - 109) / 32).toDouble();
      out.add(RainPoint(day.add(Duration(minutes: minutes)), mm));
    }
    return out;
  }
}

/// Google Maps Platform Weather API. Needs an API key with the Weather API enabled.
class GoogleWeather {
  GoogleWeather(this._client, this._key);
  final http.Client _client;
  final String _key;

  Uri _uri(String path, double lat, double lon, Map<String, String> extra) =>
      Uri.https('weather.googleapis.com', path, {
        'key': _key,
        'location.latitude': '$lat',
        'location.longitude': '$lon',
        'unitsSystem': 'METRIC',
        ...extra,
      });

  Future<Forecast> forecast(double lat, double lon) async {
    final res = await Future.wait([
      fetchText(_client, _uri('/v1/currentConditions:lookup', lat, lon, {})),
      fetchText(_client, _uri('/v1/forecast/hours:lookup', lat, lon, {'hours': '24', 'pageSize': '24'})),
      fetchText(_client, _uri('/v1/forecast/days:lookup', lat, lon, {'days': '10', 'pageSize': '10'})),
    ]);
    try {
      return parse(
        jsonDecode(res[0]) as Map<String, dynamic>,
        jsonDecode(res[1]) as Map<String, dynamic>,
        jsonDecode(res[2]) as Map<String, dynamic>,
      );
    } catch (_) {
      throw WeatherException('Google Weather returned data in an unexpected shape.');
    }
  }

  static Forecast parse(Map<String, dynamic> cur, Map<String, dynamic> hrs, Map<String, dynamic> dys) {
    double deg(Object? t) => ((t as Map?)?['degrees'] as num?)?.toDouble() ?? 0;
    int code(Object? cond) => googleToWmo((cond as Map?)?['type'] as String? ?? '');
    int rain(Object? p) => (((p as Map?)?['probability'] as Map?)?['percent'] as num?)?.toInt() ?? 0;

    final hours = <HourForecast>[];
    Duration offset = Duration.zero;
    for (final h in (hrs['forecastHours'] as List? ?? const [])) {
      final m = h as Map<String, dynamic>;
      final d = m['displayDateTime'] as Map<String, dynamic>;
      offset = _offset(d['utcOffset']);
      hours.add(HourForecast(
        time: DateTime(d['year'], d['month'], d['day'], d['hours'] ?? 0, d['minutes'] ?? 0),
        temperature: deg(m['temperature']),
        code: code(m['weatherCondition']),
        rainChance: rain(m['precipitation']),
      ));
    }

    DateTime local(String? iso, DateTime fallback) {
      if (iso == null) return fallback;
      final u = DateTime.parse(iso).toUtc().add(offset);
      return DateTime(u.year, u.month, u.day, u.hour, u.minute);
    }

    final days = <DayForecast>[];
    for (final x in (dys['forecastDays'] as List? ?? const [])) {
      final m = x as Map<String, dynamic>;
      final dd = m['displayDate'] as Map<String, dynamic>;
      final date = DateTime(dd['year'], dd['month'], dd['day']);
      final dayPart = m['daytimeForecast'] as Map<String, dynamic>? ?? const {};
      final night = m['nighttimeForecast'] as Map<String, dynamic>? ?? const {};
      final sun = m['sunEvents'] as Map<String, dynamic>? ?? const {};
      days.add(DayForecast(
        date: date,
        max: deg(m['maxTemperature']),
        min: deg(m['minTemperature']),
        code: code(dayPart['weatherCondition']),
        rainChance: math.max(rain(dayPart['precipitation']), rain(night['precipitation'])),
        sunrise: local(sun['sunriseTime'] as String?, date.add(const Duration(hours: 7))),
        sunset: local(sun['sunsetTime'] as String?, date.add(const Duration(hours: 19))),
      ));
    }

    final f = Forecast(
      temperature: deg(cur['temperature']),
      feelsLike: deg(cur['feelsLikeTemperature']),
      humidity: (cur['relativeHumidity'] as num?)?.toInt() ?? 0,
      wind: ((((cur['wind'] as Map?)?['speed']) as Map?)?['value'] as num?)?.toDouble() ?? 0,
      code: code(cur['weatherCondition']),
      isDay: cur['isDaytime'] as bool? ?? true,
      hours: hours,
      days: days,
      fetchedAt: DateTime.now(),
    );
    f.source = 'Google Weather';
    return f;
  }

  static Duration _offset(Object? v) {
    final s = v is String ? v.replaceAll('s', '') : null;
    return Duration(seconds: double.tryParse(s ?? '')?.round() ?? 0);
  }

  /// Maps Google condition types onto WMO codes so the UI has one vocabulary.
  static int googleToWmo(String type) => switch (type) {
        'CLEAR' => 0,
        'MOSTLY_CLEAR' => 1,
        'PARTLY_CLOUDY' => 2,
        'MOSTLY_CLOUDY' || 'CLOUDY' || 'WINDY' => 3,
        'LIGHT_RAIN' || 'LIGHT_TO_MODERATE_RAIN' => 61,
        'RAIN' || 'MODERATE_TO_HEAVY_RAIN' || 'WIND_AND_RAIN' => 63,
        'HEAVY_RAIN' || 'RAIN_PERIODICALLY_HEAVY' => 65,
        'LIGHT_RAIN_SHOWERS' || 'CHANCE_OF_SHOWERS' || 'SCATTERED_SHOWERS' => 80,
        'RAIN_SHOWERS' => 81,
        'HEAVY_RAIN_SHOWERS' => 82,
        'LIGHT_SNOW' || 'LIGHT_TO_MODERATE_SNOW' => 71,
        'SNOW' || 'MODERATE_TO_HEAVY_SNOW' => 73,
        'HEAVY_SNOW' || 'SNOWSTORM' || 'SNOW_PERIODICALLY_HEAVY' || 'HEAVY_SNOW_STORM' || 'BLOWING_SNOW' => 75,
        'LIGHT_SNOW_SHOWERS' || 'CHANCE_OF_SNOW_SHOWERS' || 'SCATTERED_SNOW_SHOWERS' || 'SNOW_SHOWERS' || 'HEAVY_SNOW_SHOWERS' => 85,
        'RAIN_AND_SNOW' => 66,
        'HAIL' || 'HAIL_SHOWERS' => 96,
        'THUNDERSTORM' || 'THUNDERSHOWER' || 'LIGHT_THUNDERSTORM_RAIN' || 'SCATTERED_THUNDERSTORMS' || 'HEAVY_THUNDERSTORM' => 95,
        _ => 3,
      };
}

/// WMO weather interpretation codes.
class WeatherCode {
  static String label(int code) => switch (code) {
        0 => 'Clear',
        1 => 'Mostly clear',
        2 => 'Partly cloudy',
        3 => 'Overcast',
        45 || 48 => 'Fog',
        51 || 53 || 55 => 'Drizzle',
        56 || 57 => 'Freezing drizzle',
        61 => 'Light rain',
        63 => 'Rain',
        65 => 'Heavy rain',
        66 || 67 => 'Freezing rain',
        71 => 'Light snow',
        73 => 'Snow',
        75 => 'Heavy snow',
        77 => 'Snow grains',
        80 || 81 => 'Showers',
        82 => 'Heavy showers',
        85 || 86 => 'Snow showers',
        95 => 'Thunderstorm',
        96 || 99 => 'Thunderstorm, hail',
        _ => 'Unknown',
      };

  static IconData icon(int code, {bool isDay = true}) => switch (code) {
        0 || 1 => isDay ? Icons.wb_sunny_rounded : Icons.nightlight_round,
        2 => isDay ? Icons.wb_cloudy_rounded : Icons.nights_stay_rounded,
        3 => Icons.cloud_rounded,
        45 || 48 => Icons.foggy,
        >= 51 && <= 67 => Icons.water_drop_rounded,
        >= 71 && <= 77 => Icons.ac_unit_rounded,
        80 || 81 || 82 => Icons.grain_rounded,
        85 || 86 => Icons.ac_unit_rounded,
        >= 95 => Icons.thunderstorm_rounded,
        _ => Icons.cloud_queue_rounded,
      };

  /// Background gradient for the current conditions card.
  static List<Color> gradient(int code, bool isDay) {
    if (!isDay) return const [Color(0xFF1E2A44), Color(0xFF2F3F63)];
    if (code <= 1) return const [Color(0xFF3B83D1), Color(0xFF6FB1E8)];
    if (code <= 3) return const [Color(0xFF5B7A99), Color(0xFF8AA4BD)];
    if (code <= 48) return const [Color(0xFF7A8590), Color(0xFFA3ACB4)];
    if (code >= 95) return const [Color(0xFF3B3F55), Color(0xFF5E6380)];
    if (code >= 71 && code <= 86 && code != 80 && code != 81 && code != 82) {
      return const [Color(0xFF7C93AD), Color(0xFFB4C4D6)];
    }
    return const [Color(0xFF45607E), Color(0xFF6E89A6)];
  }
}
