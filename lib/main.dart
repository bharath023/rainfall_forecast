import 'package:flutter/material.dart';

import 'api.dart';
import 'models.dart';
import 'widgets.dart';

void main() => runApp(const RainfallApp());

class RainfallApp extends StatelessWidget {
  const RainfallApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rainfall Forecast',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF1565C0), useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF1565C0),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _api = OpenMeteoApi();
  Place _place = const Place(
      name: 'Bengaluru', admin: 'Karnataka', country: 'India', lat: 12.97, lon: 77.59);
  late Future<ForecastData> _future;

  @override
  void initState() {
    super.initState();
    _future = _api.fetchForecast(_place);
  }

  Future<void> _reload() async {
    final f = _api.fetchForecast(_place);
    setState(() => _future = f);
    try {
      await f;
    } catch (_) {
      // FutureBuilder shows the error.
    }
  }

  Future<void> _pickPlace() async {
    final place = await showSearch<Place?>(
      context: context,
      delegate: _PlaceSearch(_api),
    );
    if (place == null) return;
    _place = place;
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_place.label, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: _pickPlace),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<ForecastData>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return ListView(children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Could not load forecast:\n${snap.error}\n\nPull down to retry.'),
                ),
              ]);
            }
            final data = snap.data!;
            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                TodayCard(data: data),
                HourlyChart(data: data),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                  child: Text('Daily · weighted blend of 6 models',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                for (var i = 0; i < data.days.length; i++) DayTile(data: data, index: i),
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Data: Open-Meteo.com · ECMWF (CC-BY 4.0), NOAA, DWD, ECCC, JMA',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PlaceSearch extends SearchDelegate<Place?> {
  final OpenMeteoApi api;
  _PlaceSearch(this.api) : super(searchFieldLabel: 'Search any city worldwide');

  @override
  List<Widget> buildActions(BuildContext context) =>
      [IconButton(icon: const Icon(Icons.clear), onPressed: () => query = '')];

  @override
  Widget buildLeading(BuildContext context) =>
      IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => close(context, null));

  @override
  Widget buildResults(BuildContext context) => _results();

  @override
  Widget buildSuggestions(BuildContext context) => _results();

  Widget _results() {
    if (query.trim().length < 2) {
      return const Center(child: Text('Type at least 2 letters'));
    }
    return FutureBuilder<List<Place>>(
      future: api.searchPlaces(query.trim()),
      builder: (context, snap) {
        if (!snap.hasData) {
          return snap.hasError
              ? Center(child: Text('${snap.error}'))
              : const Center(child: CircularProgressIndicator());
        }
        final places = snap.data!;
        if (places.isEmpty) return const Center(child: Text('No places found'));
        return ListView(children: [
          for (final p in places)
            ListTile(
              leading: const Icon(Icons.place_outlined),
              title: Text(p.name),
              subtitle: Text(p.label),
              onTap: () => close(context, p),
            ),
        ]);
      },
    );
  }
}
