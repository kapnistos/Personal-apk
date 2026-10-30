import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

import '../../core/db/database.dart';
import '../../core/format.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'weather_service.dart';

String formatTemp(double celsius, TempUnit unit, {bool withUnit = false}) {
  final v = unit == TempUnit.celsius ? celsius : celsius * 9 / 5 + 32;
  final s = '${v.round()}°';
  return withUnit ? '$s${unit == TempUnit.celsius ? 'C' : 'F'}' : s;
}

class WeatherPage extends StatefulWidget {
  const WeatherPage({super.key});

  @override
  State<WeatherPage> createState() => _WeatherPageState();
}

class _WeatherPageState extends State<WeatherPage> {
  // Kept so a redraw doesn't start a new database query.
  late final _cities = context.db.watchCities();

  void _select(int id) => context.settings.setRaw('weather.city', '$id');

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<City>>(
      stream: _cities,
      builder: (context, snap) {
        final cities = snap.data ?? const <City>[];
        final city = selectedCity(context, cities);
        return Scaffold(
          appBar: AppBar(
            title: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => showLocationPicker(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.place_outlined, size: 20),
                    const SizedBox(width: 6),
                    Flexible(child: Text(city?.name ?? 'Weather', overflow: TextOverflow.ellipsis)),
                    const Icon(Icons.arrow_drop_down_rounded),
                  ],
                ),
              ),
            ),
            actions: [
              IconButton(
                tooltip: 'Use my location',
                icon: const Icon(Icons.my_location_rounded),
                onPressed: () => useMyLocation(context),
              ),
              IconButton(
                tooltip: 'Manage cities',
                icon: const Icon(Icons.tune_rounded),
                onPressed: () => showCityManager(context),
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: !snap.hasData
              ? const SizedBox.shrink()
              : cities.isEmpty
              ? EmptyState(
                  icon: Icons.location_city_rounded,
                  title: 'No cities yet',
                  message: 'Add a city to see its forecast.',
                  action: FilledButton.icon(
                    onPressed: () => showCityManager(context),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add city'),
                  ),
                )
              : Column(
                  children: [
                    if (cities.length > 1)
                      SizedBox(
                        height: 48,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          scrollDirection: Axis.horizontal,
                          itemCount: cities.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemBuilder: (context, i) {
                            final c = cities[i];
                            return Center(
                              child: ChoiceChip(
                                label: Text(c.name),
                                selected: c.id == city!.id,
                                showCheckmark: false,
                                onSelected: (_) => _select(c.id),
                              ),
                            );
                          },
                        ),
                      ),
                    Expanded(
                      child: _CityForecast(key: ValueKey(city!.id), city: city),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _CityForecast extends StatefulWidget {
  const _CityForecast({super.key, required this.city});
  final City city;

  @override
  State<_CityForecast> createState() => _CityForecastState();
}

class _CityForecastState extends State<_CityForecast> {
  Forecast? _forecast;
  String? _error;

  @override
  void initState() {
    super.initState();
    _forecast = WeatherService.instance.cached(widget.city.latitude, widget.city.longitude);
    if (_forecast == null) _load();
  }

  final _nowcastKey = GlobalKey<RainNowcastCardState>();

  Future<void> _load({bool force = false}) async {
    if (force) _nowcastKey.currentState?.reload();
    try {
      final f = await WeatherService.instance.forecast(widget.city.latitude, widget.city.longitude, force: force);
      if (mounted) {
        setState(() {
          _forecast = f;
          _error = null;
        });
      }
    } on WeatherException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Something went wrong loading the forecast.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = _forecast;
    if (f == null) {
      if (_error != null) {
        return EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Forecast unavailable',
          message: _error!,
          action: OutlinedButton(
            onPressed: () {
              setState(() => _error = null);
              _load(force: true);
            },
            child: const Text('Try again'),
          ),
        );
      }
      return const SingleChildScrollView(child: Skeleton(lines: 6, padding: EdgeInsets.fromLTRB(16, 12, 16, 12)));
    }
    final unit = context.settings.tempUnit;
    return RefreshIndicator(
      onRefresh: () => _load(force: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          ContentWidth(
            child: _NowCard(city: widget.city, f: f, unit: unit),
          ),
          const SizedBox(height: 16),
          ContentWidth(
            child: RainNowcastCard(key: _nowcastKey, city: widget.city),
          ),
          const SizedBox(height: 16),
          ContentWidth(
            child: _HourlyStrip(f: f, unit: unit),
          ),
          const SizedBox(height: 16),
          ContentWidth(
            child: _DailyList(f: f, unit: unit),
          ),
          const SizedBox(height: 16),
          ContentWidth(
            child: _Details(f: f, unit: unit),
          ),
          const SizedBox(height: 16),
          const ContentWidth(child: WeatherSourcesCard()),
          const SizedBox(height: 12),
          ContentWidth(
            child: Text(
              ['Updated ${DateFormat.Hm().format(f.fetchedAt)} · ${f.source}', ?f.note].join('\n'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Palette.of(context).muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _NowCard extends StatelessWidget {
  const _NowCard({required this.city, required this.f, required this.unit});
  final City city;
  final Forecast f;
  final TempUnit unit;

  @override
  Widget build(BuildContext context) {
    final today = f.days.firstOrNull;
    const white = Colors.white;
    final dim = Colors.white.withValues(alpha: 0.78);
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: WeatherCode.gradient(f.code, f.isDay),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(city.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: white)),
          if (city.region.isNotEmpty) Text(city.region, style: TextStyle(color: dim)),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatTemp(f.temperature, unit),
                style: const TextStyle(
                  fontSize: 76,
                  height: 0.95,
                  fontWeight: FontWeight.w300,
                  color: white,
                  letterSpacing: -3,
                ),
              ),
              const Spacer(),
              Icon(WeatherCode.icon(f.code, isDay: f.isDay), size: 56, color: white),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            WeatherCode.label(f.code),
            style: const TextStyle(color: white, fontSize: 17, fontWeight: FontWeight.w600),
          ),
          if (today != null)
            Text(
              'High ${formatTemp(today.max, unit)} · Low ${formatTemp(today.min, unit)} · Feels like ${formatTemp(f.feelsLike, unit)}',
              style: TextStyle(color: dim),
            ),
        ],
      ),
    );
  }
}

class _HourlyStrip extends StatelessWidget {
  const _HourlyStrip({required this.f, required this.unit});
  final Forecast f;
  final TempUnit unit;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Section(
      title: 'Next 24 hours',
      child: SizedBox(
        height: 108,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: f.hours.length,
          separatorBuilder: (_, _) => const SizedBox(width: 4),
          itemBuilder: (context, i) {
            final h = f.hours[i];
            final day = f.days.where((d) => dateOnly(d.date) == dateOnly(h.time)).firstOrNull;
            final isDay = day == null || (h.time.isAfter(day.sunrise) && h.time.isBefore(day.sunset));
            return SizedBox(
              width: 56,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    i == 0 ? 'Now' : DateFormat.H().format(h.time),
                    style: TextStyle(color: p.muted, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  Icon(WeatherCode.icon(h.code, isDay: isDay), size: 22, color: p.ink),
                  SizedBox(
                    height: 16,
                    child: h.rainChance >= 20
                        ? Text(
                            '${h.rainChance}%',
                            style: const TextStyle(
                              fontSize: 12,
                              color: TileColors.weather,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        : null,
                  ),
                  Text(
                    formatTemp(h.temperature, unit),
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DailyList extends StatelessWidget {
  const _DailyList({required this.f, required this.unit});
  final Forecast f;
  final TempUnit unit;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    if (f.days.isEmpty) return const SizedBox.shrink();
    final lo = f.days.map((d) => d.min).reduce(math.min);
    final hi = f.days.map((d) => d.max).reduce(math.max);
    final span = math.max(1.0, hi - lo);
    return Section(
      title: '7-day forecast',
      child: Column(
        children: [
          for (final d in f.days)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              child: Row(
                children: [
                  SizedBox(
                    width: 92,
                    child: Text(friendlyDay(d.date), style: const TextStyle(fontWeight: FontWeight.w500)),
                  ),
                  Icon(WeatherCode.icon(d.code), size: 20, color: p.ink),
                  SizedBox(
                    width: 40,
                    child: d.rainChance >= 20
                        ? Text(
                            ' ${d.rainChance}%',
                            style: const TextStyle(
                              fontSize: 12,
                              color: TileColors.weather,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        : null,
                  ),
                  SizedBox(
                    width: 36,
                    child: Text(
                      formatTemp(d.min, unit),
                      textAlign: TextAlign.right,
                      style: TextStyle(color: p.muted),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, c) {
                        final left = (d.min - lo) / span * c.maxWidth;
                        final width = math.max(6.0, (d.max - d.min) / span * c.maxWidth);
                        return SizedBox(
                          height: 6,
                          child: Stack(
                            children: [
                              Container(
                                decoration: BoxDecoration(color: p.raised, borderRadius: BorderRadius.circular(3)),
                              ),
                              Positioned(
                                left: left,
                                width: math.min(width, c.maxWidth - left),
                                top: 0,
                                bottom: 0,
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(3),
                                    gradient: const LinearGradient(colors: [Color(0xFF6FB1E8), Color(0xFFE9A23B)]),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 36,
                    child: Text(formatTemp(d.max, unit), style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.f, required this.unit});
  final Forecast f;
  final TempUnit unit;

  @override
  Widget build(BuildContext context) {
    final today = f.days.firstOrNull;
    final items = [
      (Icons.thermostat_rounded, 'Feels like', formatTemp(f.feelsLike, unit)),
      (Icons.water_drop_outlined, 'Humidity', '${f.humidity}%'),
      (Icons.air_rounded, 'Wind', '${f.wind.round()} km/h'),
      if (today != null) (Icons.wb_twilight_rounded, 'Sunrise', DateFormat.Hm().format(today.sunrise)),
      if (today != null) (Icons.nights_stay_outlined, 'Sunset', DateFormat.Hm().format(today.sunset)),
      if (today != null) (Icons.umbrella_outlined, 'Rain today', '${today.rainChance}%'),
    ];
    final p = Palette.of(context);
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth > 560 ? 3 : 2;
        final w = (c.maxWidth - (cols - 1) * 10) / cols;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final (icon, label, value) in items)
              SizedBox(
                width: w,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Icon(icon, size: 20, color: p.muted),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(label, style: TextStyle(color: p.muted, fontSize: 13)),
                              Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

Future<void> showCityManager(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => Hub(db: context.db, settings: context.settings, child: const _CityManager()),
  );
}

class _CityManager extends StatefulWidget {
  const _CityManager();

  @override
  State<_CityManager> createState() => _CityManagerState();
}

class _CityManagerState extends State<_CityManager> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<Place> _results = [];
  bool _searching = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(text));
  }

  Future<void> _search(String text) async {
    if (text.trim().length < 2) {
      setState(() {
        _results = [];
        _error = null;
      });
      return;
    }
    setState(() => _searching = true);
    try {
      final r = await WeatherService.instance.search(text);
      if (mounted && _controller.text == text) {
        setState(() {
          _results = r;
          _error = null;
        });
      }
    } on WeatherException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Search is not working right now. Try again in a moment.');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final db = context.db;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text('Cities', style: Theme.of(context).textTheme.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _controller,
                onChanged: _onChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search for a city',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : null,
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: Text(_error!, style: TextStyle(color: p.danger)),
              ),
            Flexible(
              child: _controller.text.trim().length >= 2
                  ? ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      children: [
                        for (final r in _results)
                          ListTile(
                            leading: const Icon(Icons.place_outlined),
                            title: Text(r.name),
                            subtitle: Text(r.region),
                            trailing: const Icon(Icons.add_rounded),
                            onTap: () async {
                              await db.addCity(r.name, r.region, r.latitude, r.longitude);
                              _controller.clear();
                              setState(() => _results = []);
                            },
                          ),
                        if (_results.isEmpty && !_searching && _error == null)
                          Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'No matches',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: p.muted),
                            ),
                          ),
                      ],
                    )
                  : StreamBuilder<List<City>>(
                      stream: db.watchCities(),
                      builder: (context, snap) {
                        final cities = snap.data ?? const <City>[];
                        return ReorderableListView.builder(
                          shrinkWrap: true,
                          buildDefaultDragHandles: false,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: cities.length,
                          onReorderItem: (from, to) {
                            final list = [...cities];
                            list.insert(to, list.removeAt(from));
                            db.reorderCities(list);
                          },
                          itemBuilder: (context, i) {
                            final c = cities[i];
                            return ListTile(
                              key: ValueKey(c.id),
                              leading: ReorderableDragStartListener(
                                index: i,
                                child: const Icon(Icons.drag_indicator_rounded),
                              ),
                              title: Text(c.name),
                              subtitle: c.region.isEmpty ? null : Text(c.region),
                              trailing: IconButton(
                                tooltip: 'Remove',
                                icon: const Icon(Icons.close_rounded),
                                onPressed: () => db.deleteCity(c.id),
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

/// Rain over the next few hours, minute by minute where radar data exists.
class RainNowcastCard extends StatefulWidget {
  const RainNowcastCard({super.key, required this.city});
  final City city;

  @override
  State<RainNowcastCard> createState() => RainNowcastCardState();
}

class RainNowcastCardState extends State<RainNowcastCard> {
  Nowcast? _data;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    reload(force: false);
  }

  Future<void> reload({bool force = true}) async {
    try {
      final n = await WeatherService.instance.nowcast(widget.city.latitude, widget.city.longitude, force: force);
      if (mounted) {
        setState(() {
          _data = n;
          _failed = false;
        });
      }
    } on WeatherException {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final n = _data;
    if (n == null) {
      if (_failed) return const SizedBox.shrink();
      return const Section(title: 'Rain, next hours', child: SizedBox(height: 120));
    }
    final maxMm = n.points.fold<double>(2, (m, x) => math.max(m, x.mmPerHour));
    return Section(
      title: 'Rain, next hours',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(n.summary(DateFormat.Hm().format), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            const SizedBox(height: 12),
            SizedBox(
              height: 64,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final x in n.points)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 0.75),
                        child: Container(
                          // Square-root scale keeps drizzle visible next to downpours.
                          height: x.mmPerHour < 0.05 ? 2 : 4 + 60 * math.sqrt(x.mmPerHour / maxMm),
                          decoration: BoxDecoration(
                            color: x.mmPerHour < 0.05 ? p.raised : TileColors.weather,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            if (n.points.isNotEmpty)
              Row(
                children: [
                  Text('Now', style: TextStyle(color: p.muted, fontSize: 12.5)),
                  const Spacer(),
                  Text(
                    DateFormat.Hm().format(n.points[n.points.length ~/ 2].time),
                    style: TextStyle(color: p.muted, fontSize: 12.5),
                  ),
                  const Spacer(),
                  Text(DateFormat.Hm().format(n.points.last.time), style: TextStyle(color: p.muted, fontSize: 12.5)),
                ],
              ),
            const SizedBox(height: 4),
            Text(n.source, style: TextStyle(color: p.muted, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

/// The city the person picked last, or the first one.
City? selectedCity(BuildContext context, List<City> cities) {
  final id = int.tryParse(context.settings.raw('weather.city') ?? '');
  return cities.where((c) => c.id == id).firstOrNull ?? cities.firstOrNull;
}

/// Adds (or moves) a "My location" city at the device position and selects it.
Future<void> useMyLocation(BuildContext context) async {
  final db = context.db;
  final settings = context.settings;
  final messenger = ScaffoldMessenger.of(context);
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      messenger.showSnackBar(const SnackBar(content: Text('Location is turned off on this device.')));
      return;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      messenger.showSnackBar(const SnackBar(content: Text('Hub needs location permission for this.')));
      return;
    }
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 20)),
    );
    final name = await WeatherService.instance.placeName(pos.latitude, pos.longitude) ?? 'My location';
    final cities = await db.watchCities().first;
    final existing = cities.where((c) => c.region == 'Current location').firstOrNull;
    if (existing != null) {
      await db.updateCity(existing.copyWith(name: name, latitude: pos.latitude, longitude: pos.longitude));
      await settings.setRaw('weather.city', '${existing.id}');
    } else {
      await db.addCity(name, 'Current location', pos.latitude, pos.longitude);
      final added = (await db.watchCities().first).where((c) => c.region == 'Current location').first;
      await settings.setRaw('weather.city', '${added.id}');
    }
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          e is TimeoutException
              ? 'Finding your location took too long. Try again outside.'
              : 'Could not get your location.',
        ),
      ),
    );
  }
}

/// A sheet listing saved places, with "use my location" and "add a city".
void showLocationPicker(BuildContext context) {
  final db = context.db;
  final settings = context.settings;
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (sheet) => Hub(
      db: db,
      settings: settings,
      child: StreamBuilder<List<City>>(
        stream: db.watchCities(),
        builder: (sheet, snap) {
          final cities = snap.data ?? const <City>[];
          final current = selectedCity(sheet, cities);
          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  leading: const Icon(Icons.my_location_rounded),
                  title: const Text('Use my location'),
                  onTap: () {
                    Navigator.pop(sheet);
                    useMyLocation(context);
                  },
                ),
                const Divider(),
                for (final c in cities)
                  ListTile(
                    leading: Icon(
                      c.id == current?.id ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                      color: c.id == current?.id ? TileColors.weather : null,
                    ),
                    title: Text(c.name),
                    subtitle: c.region.isEmpty ? null : Text(c.region),
                    onTap: () {
                      settings.setRaw('weather.city', '${c.id}');
                      Navigator.pop(sheet);
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.add_location_alt_outlined),
                  title: const Text('Add or remove cities'),
                  onTap: () {
                    Navigator.pop(sheet);
                    showCityManager(context);
                  },
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

/// Says where each part of the forecast comes from, and lets you add the Google key.
class WeatherSourcesCard extends StatelessWidget {
  const WeatherSourcesCard({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final settings = context.settings;
    final hasGoogle = settings.googleWeatherKey.isNotEmpty;
    Widget row(IconData icon, String title, String body) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: TileColors.weather),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(body, style: TextStyle(color: p.muted, fontSize: 14, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
    return Section(
      title: 'Where the forecast comes from',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            row(
              Icons.grain_rounded,
              'Next 4 hours: Buienradar',
              'Rain radar for the next 2 hours (Netherlands and Belgium), then 15-minute steps up to 4 hours.',
            ),
            row(
              Icons.calendar_view_week_rounded,
              hasGoogle ? 'Hours and days ahead: Google Weather' : 'Hours and days ahead: Open-Meteo',
              hasGoogle
                  ? 'Google Weather API with your own key. If Google fails, Hub falls back to Open-Meteo.'
                  : 'Free and good. Add a Google Weather API key to use Google\'s forecast instead.',
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => editGoogleWeatherKey(context),
                icon: const Icon(Icons.key_rounded, size: 18),
                label: Text(hasGoogle ? 'Change Google key' : 'Add Google key'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> editGoogleWeatherKey(BuildContext context) async {
  final settings = context.settings;
  final c = TextEditingController(text: settings.googleWeatherKey);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Google Weather API key'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'In Google Cloud Console: create a project, enable "Weather API", then '
            'APIs & Services → Credentials → Create API key. Google gives a free monthly allowance.',
            style: TextStyle(height: 1.4),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: c,
            decoration: const InputDecoration(labelText: 'API key'),
          ),
        ],
      ),
      actions: [
        if (settings.googleWeatherKey.isNotEmpty)
          TextButton(
            onPressed: () {
              c.text = '';
              Navigator.pop(context, true);
            },
            child: const Text('Remove'),
          ),
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
      ],
    ),
  );
  if (ok == true) {
    await settings.setGoogleWeatherKey(c.text);
    WeatherService.instance.clearCache();
  }
}
