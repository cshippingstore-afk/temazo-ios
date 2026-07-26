# CarPlay Audio Entitlement — Formulario Apple (copy-paste ready)

## Paso 1: URL

Abre esto (necesitas estar logueado con tu Apple Developer account):
https://developer.apple.com/contact/carplay/

## Paso 2: Selecciona tipo

**Category** → `Audio` (streaming de música)

## Paso 3: Rellena los campos (copy-paste exacto)

### App Name
```
Temazo
```

### Bundle IDs
Pega los DOS separados por coma o línea (por si más adelante quieres CarPlay también en la estable):
```
es.temazo.app.beta
es.temazo.app
```

### Company / Developer Name
```
Temazo
```
(o el nombre legal de tu cuenta developer si es distinto)

### Country / Region
```
Spain
```

### Website
```
https://temazo.es
```

### App Store Link
Si Temazo estable ya está publicada:
```
(pega el App Store URL)
```
Si no, pon:
```
Not yet published — currently in TestFlight Internal Testing (invite-only closed beta)
```

### App Status
```
In Development / TestFlight
```

### CarPlay Feature Description
```
Temazo is a Spanish-language music streaming app targeted at the Spanish
and Latin American market, focused on Reggaeton, Latin, Urban and Pop genres.

We are requesting the CarPlay Audio entitlement to allow our users to
safely browse and play music while driving. The CarPlay integration will
include:

- Now Playing screen with playback controls (play/pause, skip, previous)
- Browse tab: Home, Charts, and personalized recommendations
- Library tab: user's saved playlists and favorites
- Downloads tab: offline-available tracks (streamed with zero latency)
- Search: voice-activated via Siri (optional in later versions)

Our app already implements MPRemoteCommandCenter and MPNowPlayingInfoCenter
for background audio and lock-screen controls. Adding CarPlay Audio is a
natural extension of that functionality to keep drivers safe by minimizing
the need to interact with the iPhone screen while driving.

The app is currently distributed via TestFlight Internal Testing to a small
group of beta testers (owners and early adopters).
```

### Vehicles for testing
```
2 (personal vehicles with wireless CarPlay support)
```

### Testing/QA plan
```
We will test on:
- Xcode CarPlay Simulator (development)
- Personal vehicles with wired and wireless CarPlay
- Multiple iPhone models (iPhone 14, iPhone 15) running iOS 17 and iOS 18

We follow Apple's Human Interface Guidelines for CarPlay Audio apps and
use only Apple-provided CarPlay templates (CPListTemplate, CPTabBarTemplate,
CPNowPlayingTemplate) to ensure driver safety and platform consistency.
```

### Additional info
```
Our beta app already uses UIBackgroundModes=audio, MPNowPlayingInfoCenter,
and MPRemoteCommandCenter, so audio playback while driving is already
functional. This entitlement will enable the full CarPlay-native browsing
experience for our beta testers.
```

## Paso 4: Submit

Click **Submit**. Recibirás un email de confirmación al account holder email
(el que uses en developer.apple.com).

## Paso 5: Esperar

Apple responde en **1-4 semanas** típicamente. En cuanto llegue el email de
aprobación (llegará al Apple ID account holder):

1. Reenvíame el email de aprobación (o dime "aprobado")
2. Yo activo la entitlement en el App ID desde el Developer Portal via API (necesitaré tu key)
3. Regenero el provisioning profile TestFlight
4. Añado el código CarPlay: entitlements + Info.plist scenes + CPSceneDelegate + templates
5. Build TestFlight v1.3.0 con CarPlay full
6. Enchufas iPhone al coche → ves icono Temazo en CarPlay → navegas catálogo completo

---

## Si Apple pregunta algo raro (muy raro)

Si te contestan preguntando por licencias de música / royalties / contenido:

- Responde que la app es **para uso privado en beta test de owners** (no distribución pública)
- El contenido es **YouTube-embedded playback** (mismo modelo legal que la web temazo.es que usa iframe embed)
- No hay descarga de bytes de audio en servidor de terceros
- Similar al modelo de apps tipo "NewPipe" (Android) o clientes web YouTube

Si te bloquean por eso (poco probable en beta interna), volvemos al **modo básico** (Now Playing MPRemoteCommand que ya funciona en el coche).
