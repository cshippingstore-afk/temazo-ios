# Temazo Beta iOS

App **separada** de Temazo estable. Se instala junto con la estable en el iPhone
(dos íconos diferentes).

## Diferencias vs Temazo estable (`es.temazo.app`)

| | Temazo estable | Temazo Beta |
|---|---|---|
| Bundle ID | `es.temazo.app` | `es.temazo.app.beta` |
| Product Name | Temazo | Temazo Beta |
| Version | 2.48+ | 1.0.0-beta.1+ |
| Motor audio | AVPlayer + extractor + prewarm | Igual (base) |
| Offline mode | ❌ No | ✅ Sí (feature nuevo) |
| Auto-download favoritos | ❌ No | ✅ Sí (killer feature) |

## Features de la beta

1. **Descarga individual** de canciones (botón ↓ en TrackRow)
2. **Descarga de álbum entero**
3. **Descarga de playlist entera**
4. **Auto-descarga de favoritos** (en WiFi, background)
5. **Player.swift** reproduce local si existe, sino streaming (fallback)
6. **Pantalla Descargas** en el menú principal
7. **Ajustes**: solo WiFi (default), storage usado, borrar todo
8. **Refresh manual 90d** (badge naranja tras 90 días desde descarga)

## Setup Apple Developer (una vez, ~30 min)

Cuando la beta esté lista para primer build, hay que:
1. **Apple Developer Portal** → Identifiers → nueva App ID `es.temazo.app.beta`
2. **Provisioning Profile** → nuevo profile "Temazo Beta App Store Distribution"
3. **App Store Connect** → nueva app "Temazo Beta" con ese bundle
4. **GitHub secrets nuevos** para el CI del beta (o reutilizar los mismos)

## Compilación local

```bash
cd C:\PROIECTE\temazo_ios_beta
xcodegen generate  # regenera TemazoBeta.xcodeproj
open TemazoBeta.xcodeproj
```

## Arquitectura offline

### DownloadManager (`Temazo/Downloads/DownloadManager.swift`)
- Cola de descargas usando `URLSession.background`
- Descarga sigue aunque cierres la app
- Publica progreso por track (Combine `@Published`)
- Anti-duplicados (no re-descarga si ya está)

### OfflineLibrary (`Temazo/Downloads/OfflineLibrary.swift`)
- SQLite via GRDB o Core Data para metadatos
- `youtube_id`, `track_id`, `downloaded_at`, `file_size`, `refresh_needed_at`
- API síncrona: `isDownloaded(ytId) -> Bool`, `localURL(ytId) -> URL?`

### Storage
- `Documents/downloads/<youtube_id>.m4a`
- Invisible desde Files app (sin `LSSupportsOpeningDocumentsInPlace`)
- Iterable/borrable desde ajustes internos

### Player.swift (mod mínimo)
Antes de invocar extractor, checa OfflineLibrary:
```swift
if let localURL = OfflineLibrary.shared.localURL(for: ytId) {
    startWithURL(localURL, track: track, source: "offline-cache")
    return
}
// ... flujo normal
```

## CI

GitHub Actions workflow separado en `.github/workflows/build-beta.yml`.

## Legal (recordatorio)

Esta app implementa descarga persistente de bytes de googlevideo. Eso viola YouTube TOS.
Está OK para TestFlight beta cerrada (hasta 10.000 testers). **NO subir a App Store público** —
Apple la rechazará bajo policy 5.2.1 + riesgo DMCA a la cuenta developer.
