# Temazo iOS — Native Swift/SwiftUI clone

App iOS NATIVA (Swift / SwiftUI), clon funcional y de diseño de la app Android (Kotlin/Compose).
**No es un wrapper webview**. Reproductor real con `WKWebView` headless cargando `temazo.es/_app_player.html`
+ `AVAudioSession` background audio + `MPNowPlayingInfoCenter` lock-screen + `MPRemoteCommandCenter` remote.

## Arquitectura

- `Temazo/App/` — `@main App`, AppDelegate (crash logger)
- `Temazo/Theme/` — colores neon (mismos hex que Android)
- `Temazo/Data/` — Models (Track, Playlist), API client (URLSession + cookie jar), Auth, Favorites, Settings, LRC parser
- `Temazo/Audio/` — Player (WKWebView + JS bridge), AudioSessionManager, NowPlayingManager, PlayerState
- `Temazo/UI/` — MainScreen + tabs (Home, Search, Account) + Components (MiniPlayer, FullPlayer, TrackRow, TrackCard, TopBar, Settings, Register)
- `Temazo/Resources/` — Assets.xcassets, Localizable.strings (es)
- `project.yml` — XcodeGen spec (genera `Temazo.xcodeproj` en CI sin Mac)
- `_capacitor_backup/` — la app vieja Capacitor (referencia, sin compilar)

## Build automático en CI (sin Mac)

Cada push a `main`/`master` dispara GitHub Actions:

1. Instala XcodeGen → genera `Temazo.xcodeproj` desde `project.yml`
2. Genera placeholder `AppIcon-1024.png` (ImageMagick) y `silent.m4a` (ffmpeg)
3. Firma con la **App Store Connect API Key** (Automatic Signing, sin provisioning manual)
4. Archiva + exporta `.ipa` firmada
5. Sube a **TestFlight** → instalable en iPhones invitados

Secrets requeridos (ya configurados):
- `APPSTORE_API_KEY_ID` — Key ID de la API key
- `APPSTORE_API_ISSUER_ID` — Issuer ID
- `APPSTORE_API_KEY_P8` — contenido del `.p8`
- `APP_STORE_TEAM_ID` — Team ID del developer account

## Trigger manual sin subir a TestFlight

GitHub Actions → "Build iOS" → Run workflow → `upload_testflight = false` → solo artifact `.ipa`.

## Local dev (requiere Mac)

```bash
brew install xcodegen
xcodegen generate
open Temazo.xcodeproj
```

## Paridad con Android

| Android (Kotlin) | iOS (Swift) | Estado |
|---|---|---|
| `MainActivity` + Compose | `TemazoApp` + SwiftUI | ✓ |
| `Player.kt` (WebView + YT iframe) | `Player.swift` (WKWebView + JS bridge) | ✓ |
| `AudioService` (foreground service + MediaSession) | `AudioSessionManager` + `NowPlayingManager` + Background Audio mode | ✓ |
| `TemazoApi` (Retrofit + cookies) | `TemazoAPI` (URLSession + HTTPCookieStorage) | ✓ |
| `AuthRepository` | `AuthRepository` (`@MainActor ObservableObject`) | ✓ |
| `Favorites` (DataStore) | `FavoritesRepo` (UserDefaults) | ✓ |
| `SettingsRepo` (crossfade) | `SettingsRepo` (UserDefaults) | ✓ |
| `LrcParser` | `LRCParser` | ✓ |
| `MainScreen` (3 tabs + MiniPlayer + FullPlayer overlay) | `MainScreen` igual | ✓ |
| `HomeScreen` + chips géneros | `HomeScreen` igual | ✓ |
| `SearchScreen` con debounce 300ms | igual | ✓ |
| `AccountScreen` + `RegisterScreen` | igual | ✓ |
| `SettingsScreen` (crossfade) | igual | ✓ |
| `MiniPlayer` + `FullPlayer` (con LyricsView) | igual | ✓ |
| Crash handler `:crash` activity | `NSSetUncaughtExceptionHandler` + temp crash file | ✓ |
| `AppUpdater` APK auto-install | N/A en iOS (App Store/TestFlight gestionan) | ⊘ |
| `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | N/A en iOS | ⊘ |
| `SYSTEM_ALERT_WINDOW` overlay 4×4px | Background Audio mode + silent.m4a loop | ✓ (alternativo) |

## Notas

- **Solo testing por ahora** (TestFlight). No subir a App Store sin auditoría legal de uso de YouTube iframe.
- `silent.m4a` (1s mudo) se generan en CI para que iOS reconozca la app como productora de audio en background.
- El bundle ID `es.temazo.app` debe estar **registrado en developer.apple.com → Identifiers** y la app debe existir en **App Store Connect** antes del primer upload exitoso.
