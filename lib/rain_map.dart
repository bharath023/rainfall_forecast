import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import 'forecast_grid.dart';
import 'models.dart';

enum RainLayer { forecast, radar, satellite }

class RadarFrame {
  final DateTime time;
  final String tileUrl;
  const RadarFrame(this.time, this.tileUrl);
}

/// RainViewer's free radar mosaic: the past ~2 hours in 10-minute frames.
/// The free API serves radar up to zoom 7 and no longer includes nowcast
/// frames. Coverage is mainly North America, Europe, Australia and parts of
/// Asia.
Future<List<RadarFrame>> fetchRadarFrames() async {
  final res = await http
      .get(Uri.parse('https://api.rainviewer.com/public/weather-maps.json'))
      .timeout(const Duration(seconds: 15));
  if (res.statusCode != 200) throw Exception('Radar HTTP ${res.statusCode}');
  final j = jsonDecode(res.body) as Map<String, dynamic>;
  final host = j['host'] as String;
  final radar = j['radar'] as Map<String, dynamic>;
  final frames = [
    ...(radar['past'] as List? ?? const []),
    ...(radar['nowcast'] as List? ?? const []),
  ];
  return [
    for (final f in frames)
      RadarFrame(
        DateTime.fromMillisecondsSinceEpoch((f['time'] as int) * 1000),
        // 256px tiles, colour scheme 2 (Universal Blue), smoothed, with snow.
        '$host${f['path']}/256/{z}/{x}/{y}/2/1_1.png',
      ),
  ];
}

/// NASA GPM IMERG satellite rain rate (30-min, global incl. oceans), latest
/// available frame. IMERG Early arrives roughly 4–6 hours after observation.
const _imergUrl = 'https://gibs.earthdata.nasa.gov/wmts/epsg3857/best/'
    'IMERG_Precipitation_Rate_30min/default/default/'
    'GoogleMapsCompatible_Level6/{z}/{y}/{x}.png';

/// Full-screen rain map: model forecast (with model switcher and 48-hour
/// timeline), live radar, or satellite.
class RainMapView extends StatefulWidget {
  final Place place;
  const RainMapView({super.key, required this.place});

  @override
  State<RainMapView> createState() => _RainMapViewState();
}

class _RainMapViewState extends State<RainMapView> {
  final _map = MapController();
  RainLayer _layer = RainLayer.forecast;
  bool _playing = false;
  Timer? _timer;

  // Radar
  Future<List<RadarFrame>>? _radarFuture;
  List<RadarFrame> _frames = const [];
  int _frame = 0;

  // Forecast
  String _modelId = deterministicModels.first.id;
  ForecastGrid? _grid;
  LatLngBounds? _gridBounds;
  double? _gridZoom;
  int _hour = 0;
  bool _gridLoading = false;
  String? _gridError;
  Timer? _debounce;

  @override
  void didUpdateWidget(RainMapView old) {
    super.didUpdateWidget(old);
    if (old.place.lat != widget.place.lat ||
        old.place.lon != widget.place.lon) {
      _map.move(LatLng(widget.place.lat, widget.place.lon), _map.camera.zoom);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  // ---- Layer switching & playback ----------------------------------------

  void _setLayer(RainLayer layer) {
    _stop();
    setState(() => _layer = layer);
    if (layer == RainLayer.radar && _radarFuture == null) _loadRadar();
    if (layer == RainLayer.forecast) _maybeLoadGrid(force: _grid == null);
  }

  int get _frameCount => switch (_layer) {
        RainLayer.radar => _frames.length,
        RainLayer.forecast => _grid?.times.length ?? 0,
        RainLayer.satellite => 0,
      };

  int get _index => _layer == RainLayer.radar ? _frame : _hour;

  void _setIndex(int i) => setState(() {
        if (_layer == RainLayer.radar) {
          _frame = i;
        } else {
          _hour = i;
        }
      });

  void _togglePlay() {
    if (_playing) {
      _stop();
      return;
    }
    if (_frameCount < 2) return;
    setState(() => _playing = true);
    _timer = Timer.periodic(
        Duration(milliseconds: _layer == RainLayer.radar ? 700 : 900), (_) {
      if (!mounted) return;
      _setIndex((_index + 1) % _frameCount);
    });
  }

  void _stop() {
    _timer?.cancel();
    if (_playing) setState(() => _playing = false);
  }

  // ---- Radar --------------------------------------------------------------

  void _loadRadar() {
    _radarFuture = fetchRadarFrames().then((frames) {
      if (mounted) {
        setState(() {
          _frames = frames;
          _frame = frames.isEmpty ? 0 : frames.length - 1;
        });
      }
      return frames;
    });
  }

  // ---- Forecast grid ------------------------------------------------------

  /// Reloads the grid when the view leaves the fetched area or the zoom
  /// changes enough that the cells would look too coarse or too fine.
  void _maybeLoadGrid({bool force = false}) {
    if (_layer != RainLayer.forecast) return;
    final camera = _map.camera;
    final view = camera.visibleBounds;
    final covered = _gridBounds != null &&
        _gridBounds!.containsBounds(view) &&
        (camera.zoom - (_gridZoom ?? camera.zoom)).abs() < 1.5;
    if (!force && covered) return;
    _loadGrid(view, camera.zoom);
  }

  Future<void> _loadGrid(LatLngBounds view, double zoom) async {
    // Fetch a bit more than is visible so small pans don't trigger reloads.
    final padLat = (view.north - view.south) * 0.25;
    final padLon = (view.east - view.west) * 0.25;
    final sw = LatLng((view.south - padLat).clamp(-85, 85).toDouble(),
        (view.west - padLon).clamp(-180, 180).toDouble());
    final ne = LatLng((view.north + padLat).clamp(-85, 85).toDouble(),
        (view.east + padLon).clamp(-180, 180).toDouble());
    final model = _modelId;
    setState(() {
      _gridLoading = true;
      _gridError = null;
    });
    try {
      final grid = await fetchForecastGrid(modelId: model, sw: sw, ne: ne);
      if (!mounted || model != _modelId) return;
      final now = DateTime.now().toUtc();
      final keepTime = _grid != null && _hour < _grid!.times.length
          ? _grid!.times[_hour]
          : null;
      var hour = keepTime != null ? grid.times.indexOf(keepTime) : -1;
      if (hour < 0) {
        hour = grid.times.indexWhere(
            (t) => !t.isBefore(now.subtract(const Duration(minutes: 59))));
      }
      setState(() {
        _grid = grid;
        _gridBounds = LatLngBounds(sw, ne);
        _gridZoom = zoom;
        _hour = hour < 0 ? 0 : hour;
      });
    } catch (e) {
      if (mounted) setState(() => _gridError = '$e');
    } finally {
      if (mounted) setState(() => _gridLoading = false);
    }
  }

  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    if (_layer != RainLayer.forecast) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), _maybeLoadGrid);
  }

  List<Polygon> _gridPolygons() {
    final g = _grid;
    if (g == null || g.times.isEmpty) return const [];
    return [
      for (var r = 0; r < g.rows; r++)
        for (var c = 0; c < g.cols; c++)
          if (rainColor(_hour < g.values[r * g.cols + c].length
                  ? g.values[r * g.cols + c][_hour]
                  : null)
              case final color?)
            Polygon(
              points: g.cell(r, c),
              color: color.withValues(alpha: 0.55),
            ),
    ];
  }

  // ---- UI -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final center = LatLng(widget.place.lat, widget.place.lon);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: center,
            initialZoom: 5,
            minZoom: 2,
            maxZoom: 10,
            onMapReady: () => _maybeLoadGrid(force: true),
            onPositionChanged: _onPositionChanged,
          ),
          children: [
            TileLayer(
              urlTemplate: dark
                  ? 'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
                  : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.rainfall_app',
            ),
            if (_layer == RainLayer.forecast)
              PolygonLayer(polygons: _gridPolygons()),
            if (_layer == RainLayer.satellite)
              Opacity(
                opacity: 0.8,
                child: TileLayer(
                  urlTemplate: _imergUrl,
                  maxNativeZoom: 6,
                  userAgentPackageName: 'com.example.rainfall_app',
                ),
              ),
            // Mount only the current and next radar frame: enough to preload
            // the next one without loading every frame at once.
            if (_layer == RainLayer.radar && _frames.isNotEmpty)
              for (final i in {_frame, (_frame + 1) % _frames.length})
                if (i < _frames.length)
                  Opacity(
                    key: ValueKey(_frames[i].tileUrl),
                    opacity: i == _frame ? 0.75 : 0,
                    child: TileLayer(
                      urlTemplate: _frames[i].tileUrl,
                      maxNativeZoom: 7,
                      userAgentPackageName: 'com.example.rainfall_app',
                    ),
                  ),
            MarkerLayer(markers: [
              Marker(
                point: center,
                width: 36,
                height: 36,
                child:
                    const Icon(Icons.location_pin, color: Colors.red, size: 36),
              ),
            ]),
            RichAttributionWidget(attributions: [
              const TextSourceAttribution('OpenStreetMap contributors'),
              if (dark) const TextSourceAttribution('CARTO'),
              TextSourceAttribution(switch (_layer) {
                RainLayer.forecast => 'Forecast: Open-Meteo',
                RainLayer.radar => 'Radar: RainViewer',
                RainLayer.satellite => 'Satellite: NASA GPM IMERG',
              }),
            ]),
          ],
        ),
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: Center(
            child: Material(
              elevation: 3,
              borderRadius: BorderRadius.circular(24),
              color: Theme.of(context).colorScheme.surface,
              child: SegmentedButton<RainLayer>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                      value: RainLayer.forecast,
                      icon: Icon(Icons.show_chart),
                      label: Text('Forecast')),
                  ButtonSegment(
                      value: RainLayer.radar,
                      icon: Icon(Icons.radar),
                      label: Text('Radar')),
                  ButtonSegment(
                      value: RainLayer.satellite,
                      icon: Icon(Icons.satellite_alt),
                      label: Text('Satellite')),
                ],
                selected: {_layer},
                onSelectionChanged: (s) => _setLayer(s.first),
              ),
            ),
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 32,
          child: _panel(
              context,
              switch (_layer) {
                RainLayer.forecast => _forecastControls(context),
                RainLayer.radar => _radarControls(context),
                RainLayer.satellite => const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      'NASA satellite rain (IMERG) · global, including areas '
                      'without radar · latest available, usually 4–6 hours old',
                    ),
                  ),
              }),
        ),
      ],
    );
  }

  Widget _timeline(String label) => Row(children: [
        IconButton(
          icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
          onPressed: _togglePlay,
        ),
        Expanded(
          child: Slider(
            value: _index.toDouble().clamp(0, (_frameCount - 1).toDouble()),
            max: (_frameCount - 1).toDouble(),
            divisions: _frameCount > 1 ? _frameCount - 1 : null,
            onChanged: (v) {
              _stop();
              _setIndex(v.round());
            },
          ),
        ),
        Text(label),
        const SizedBox(width: 8),
      ]);

  Widget _forecastControls(BuildContext context) {
    final g = _grid;
    final label = g == null || g.times.isEmpty
        ? ''
        : DateFormat('EEE HH:mm').format(g.times[_hour].toLocal());
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          const SizedBox(width: 8),
          DropdownButton<String>(
            value: _modelId,
            underline: const SizedBox.shrink(),
            items: [
              for (final m in deterministicModels)
                DropdownMenuItem(value: m.id, child: Text(m.name)),
            ],
            onChanged: (id) {
              if (id == null || id == _modelId) return;
              _stop();
              setState(() => _modelId = id);
              _maybeLoadGrid(force: true);
            },
          ),
          const Spacer(),
          if (_gridLoading)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
        ]),
        if (_gridError != null)
          Row(children: [
            Expanded(
                child: Text('Could not load forecast map',
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error))),
            TextButton(
                onPressed: () => _maybeLoadGrid(force: true),
                child: const Text('Retry')),
          ])
        else if (g != null && g.times.length > 1)
          _timeline(label),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
          child: Row(children: [
            const Text('mm/h ', style: TextStyle(fontSize: 11)),
            for (final (text, color) in rainLegend)
              Expanded(
                child: Container(
                  height: 16,
                  color: color,
                  alignment: Alignment.center,
                  child: Text(text,
                      style:
                          const TextStyle(fontSize: 10, color: Colors.black87)),
                ),
              ),
          ]),
        ),
      ],
    );
  }

  Widget _radarControls(BuildContext context) {
    return FutureBuilder<List<RadarFrame>>(
      future: _radarFuture,
      builder: (context, snap) {
        if (snap.hasError) {
          return Row(children: [
            const Expanded(child: Text('Could not load radar')),
            TextButton(
                onPressed: () => setState(_loadRadar),
                child: const Text('Retry')),
          ]);
        }
        if (_frames.isEmpty) return const LinearProgressIndicator();
        final t = DateFormat('HH:mm').format(_frames[_frame].time);
        final latest = _frame == _frames.length - 1;
        return _timeline(latest ? '$t (latest)' : t);
      },
    );
  }

  Widget _panel(BuildContext context, Widget child) => Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(16),
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.94),
        child: Padding(padding: const EdgeInsets.all(8), child: child),
      );
}
