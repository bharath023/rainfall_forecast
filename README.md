# Rainfall Forecast (MVP)

Global rainfall forecast app in Flutter (Android + iOS). It combines six global
weather models and two ensembles, all served through the free Open-Meteo API.

**What it shows**
- **Today card:** blended rainfall, chance of rain, and how closely the models agree
- **72-hour chart:** hourly rain from each model, so you can compare
  ECMWF IFS, ECMWF AIFS (AI), GFS, ICON, GEM and JMA
- **10-day list:** a weighted blend of the models, the chance of rain (≥1 mm) and of
  heavy rain (≥10 mm) from 82 ensemble members (ECMWF ENS + GEFS), and the
  10–90% likely range. Tap a day to see each model's value.
- **City search:** any place worldwide (Open-Meteo geocoding)

## Run it

1. Install the Flutter SDK (https://docs.flutter.dev/get-started/install/windows)
   and Android Studio (for the Android SDK and an emulator). Then check your setup:
   ```
   flutter doctor
   ```
2. Generate the platform folders. This keeps the existing `lib/` code:
   ```
   cd rainfall_app
   flutter create . --project-name rainfall_app --platforms android,ios
   flutter pub get
   ```
3. Start an emulator or plug in your phone, then run:
   ```
   flutter run
   ```
4. Release builds on Android need internet permission. Add this to
   `android/app/src/main/AndroidManifest.xml`, just inside `<manifest>`:
   ```xml
   <uses-permission android:name="android.permission.INTERNET"/>
   ```

## Code layout

| File | Purpose |
|---|---|
| `lib/models.dart` | The weather models and their blend weights, plus the data classes |
| `lib/api.dart` | Open-Meteo calls: city search, multi-model forecast, ensemble |
| `lib/blend.dart` | Weighted blend, rain probability, percentiles, model agreement |
| `lib/widgets.dart` | Today card, hourly chart, daily tiles |
| `lib/main.dart` | App shell, home screen, city search |

## Next steps
- **Better blend weights:** the weights in `models.dart` are rough starting
  guesses. Replace them with weights learned by checking past forecasts against
  GPM IMERG satellite rain or rain-gauge data for each region.
- **GPS location:** add the `geolocator` package.
- **Radar map and nowcast:** add RainViewer tiles on a `flutter_map` / MapLibre map.
- **Rain alerts:** add Firebase Cloud Messaging and a small backend that checks the
  forecasts every hour.
- **Own backend:** build a Python pipeline (xarray + cfgrib) that downloads ECMWF
  Open Data and GFS directly, then applies bias correction (quantile mapping).

## Licensing
- Open-Meteo is free for non-commercial use. A commercial app needs a
  subscription or a self-hosted instance (it's open source).
- ECMWF data must be credited (CC-BY 4.0). NOAA data is public domain.
