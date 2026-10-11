import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import 'models.dart';

class RadarFrame {
  final DateTime time;
  final String tileUrl;
  const RadarFrame(this.time, this.tileUrl);
}

/// RainViewer's free radar mosaic: the past ~2 hours in 10-minute frames.
/// The free API serves radar up to zoom 7 and no longer includes nowcast frames.
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

class RadarView extends StatefulWidget {
  final Place place;
  const RadarView({super.key, required this.place});

  @override
  State<RadarView> createState() => _RadarViewState();
}

class _RadarViewState extends State<RadarView> {
  final _map = MapController();
  late Future<List<RadarFrame>> _future;
  List<RadarFrame> _frames = const [];
  int _frame = 0;
  bool _playing = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(RadarView old) {
    super.didUpdateWidget(old);
    if (old.place.lat != widget.place.lat ||
        old.place.lon != widget.place.lon) {
      _map.move(LatLng(widget.place.lat, widget.place.lon), _map.camera.zoom);
    }
  }

  void _load() {
    _timer?.cancel();
    _future = fetchRadarFrames().then((frames) {
      if (!mounted) return frames;
      setState(() {
        _frames = frames;
        _frame = frames.isEmpty ? 0 : frames.length - 1;
      });
      _startTimer();
      return frames;
    });
  }

  void _startTimer() {
    _timer?.cancel();
    if (!_playing || _frames.length < 2) return;
    _timer = Timer.periodic(const Duration(milliseconds: 700), (_) {
      if (!mounted) return;
      setState(() => _frame = (_frame + 1) % _frames.length);
    });
  }

  void _togglePlay() {
    setState(() => _playing = !_playing);
    if (_playing) {
      _startTimer();
    } else {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final center = LatLng(widget.place.lat, widget.place.lon);
    return Stack(
      children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
              initialCenter: center, initialZoom: 6, minZoom: 2, maxZoom: 10),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.rainfall_app',
            ),
            // Every frame stays mounted (invisible ones at opacity 0) so tiles
            // are preloaded and the animation does not flicker.
            for (var i = 0; i < _frames.length; i++)
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
            const RichAttributionWidget(attributions: [
              TextSourceAttribution('OpenStreetMap contributors'),
              TextSourceAttribution('Radar: RainViewer'),
            ]),
          ],
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 40,
          child: FutureBuilder<List<RadarFrame>>(
            future: _future,
            builder: (context, snap) {
              if (snap.hasError) {
                return _panel(
                    context,
                    Row(children: [
                      const Expanded(child: Text('Could not load radar')),
                      TextButton(
                          onPressed: () => setState(_load),
                          child: const Text('Retry')),
                    ]));
              }
              if (_frames.isEmpty) {
                return _panel(context, const LinearProgressIndicator());
              }
              final t = DateFormat('HH:mm').format(_frames[_frame].time);
              final latest = _frame == _frames.length - 1;
              return _panel(
                context,
                Row(children: [
                  IconButton(
                    icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                    onPressed: _togglePlay,
                  ),
                  Expanded(
                    child: Slider(
                      value: _frame.toDouble(),
                      max: (_frames.length - 1).toDouble(),
                      divisions: _frames.length > 1 ? _frames.length - 1 : null,
                      onChanged: (v) {
                        _timer?.cancel();
                        setState(() {
                          _playing = false;
                          _frame = v.round();
                        });
                      },
                    ),
                  ),
                  Text(latest ? '$t (latest)' : t),
                  const SizedBox(width: 8),
                ]),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _panel(BuildContext context, Widget child) => Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(16),
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
        child: Padding(padding: const EdgeInsets.all(8), child: child),
      );
}
