# Rainfall Forecast (MVP)

Global rainfall forecast app in Flutter (Android + iOS). It combines six global
weather models and two ensembles, all served through the free Open-Meteo API.

**What it shows**
- **Headline:** a plain sentence such as "Rain starting in about 25 min" or
  "Dry for now · rain likely on Friday (65%)", with bars for the next 3 hours
  in 15-minute steps
- **Today:** blended rainfall, chance of rain, and how closely the models agree
- **72-hour chart:** hourly rain from each model, so you can compare
  ECMWF IFS, ECMWF AIFS (AI), GFS, ICON, GEM and JMA
- **10-day list:** a weighted blend of the models, the chance of rain (≥1 mm) and of
  heavy rain (≥10 mm) from 82 ensemble members (ECMWF ENS + GEFS), and the
  10–90% likely range. Tap a day to see each model's value.
- **Location:** GPS ("my location" button, at city-level accuracy) or search for
  any place worldwide. The app remembers the last place you viewed.
- **Rain map tab** with three layers:
  - **Forecast:** model rain for the next 48 hours, with a model switcher,
    timeline and play button
  - **Radar:** the past ~2 hours from RainViewer (mainly North America, Europe,
    Australia and parts of Asia; little coverage over India)
  - **Satellite:** NASA GPM IMERG rain, global including India and the oceans,
    usually 4–6 hours old
- **Rain alerts (bell icon):** about every 30 minutes the phone checks the next
  3 hours at your saved place. It notifies you if ≥0.5 mm of rain or a ≥60% chance
  is expected, at most once every 3 hours. This runs on the phone, with no server.

## Run it

1. Install Android Studio and let it set up the Android SDK on first launch.
   Check your setup with:
   ```
   flutter doctor
   ```
2. Plug in your phone (with USB debugging on) or start an emulator, then:
   ```
   flutter run
   ```
3. To try it in a browser instead (no Android SDK needed):
   ```
   flutter run -d chrome
   ```
   Alerts are hidden in the browser because they only work on phones.

## iOS rain alerts (needs a Mac)
iOS runs background tasks through BGTaskScheduler. Before alerts work on iPhone:
- Add `fetch` and `processing` to `UIBackgroundModes` in `ios/Runner/Info.plist`.
- Add `rain-check` to `BGTaskSchedulerPermittedIdentifiers`.
- Register the task in `AppDelegate.swift`, following the `workmanager` package's
  iOS setup guide.

iOS also decides for itself how often background tasks run, so alerts on iPhone
can be less frequent than on Android. For reliable alerts on both platforms,
use a server with push notifications (see Next steps).

## Code layout

| File | Purpose |
|---|---|
| `lib/models.dart` | The weather models and their blend weights, plus the data classes |
| `lib/api.dart` | Open-Meteo calls: city search, multi-model forecast, ensemble |
| `lib/blend.dart` | Weighted blend, rain probability, percentiles, model agreement |
| `lib/widgets.dart` | Today card, hourly chart, daily tiles |
| `lib/location.dart` | GPS position and place name (BigDataCloud reverse geocoding) |
| `lib/rain_map.dart` | Rain map tab: forecast grid, radar and satellite layers |
| `lib/forecast_grid.dart` | Fetches model rain on a grid of points and colours it |
| `lib/summary.dart` | The headline sentence and 15-minute steps |
| `lib/alerts.dart` | Background rain check (workmanager) and notifications |
| `lib/storage.dart` | Saved place and alert settings (shared_preferences) |
| `lib/main.dart` | App shell, tabs, city search |

## Next steps
- **Better blend weights:** the weights in `models.dart` are rough starting
  guesses. Replace them with weights learned by checking past forecasts against
  GPM IMERG satellite rain or rain-gauge data for each region.
- **Server-side alerts:** Firebase Cloud Messaging plus a small backend, for
  reliable alerts on iOS and alerts for several saved places.
- **Own backend:** build a Python pipeline (xarray + cfgrib) that downloads ECMWF
  Open Data and GFS directly, then applies bias correction (quantile mapping).
- **Map tiles for production:** the OpenStreetMap tile servers aren't meant for
  heavy app traffic. Switch to a paid tile provider (MapTiler, Stadia, etc.) before launch.

## Licensing
- Open-Meteo is free for non-commercial use. A commercial app needs a
  subscription or a self-hosted instance (it's open source).
- ECMWF data must be credited (CC-BY 4.0). NOAA data is public domain.
- Credit RainViewer for radar and OpenStreetMap contributors for the map;
  the app shows both credits on the map.
