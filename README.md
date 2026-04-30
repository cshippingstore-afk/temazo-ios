# Temazo iOS

App iOS de Temazo (wrapper Capacitor de https://temazo.es).

## Build automático

Cada push a `main`/`master` dispara GitHub Actions que compila la `.ipa` sin necesidad de Mac.
La `.ipa` queda como artifact descargable.

## Instalar en iPhone

1. Descarga la `.ipa` desde GitHub Actions → Artifacts
2. Pásala al iPhone (AirDrop, Drive, Telegram a ti mismo)
3. Abre AltStore en el iPhone → "+" → selecciona la `.ipa` → install

## Estructura

- `capacitor.config.json` — configuración Capacitor (apunta a https://temazo.es)
- `www/` — fallback HTML (redirect a temazo.es)
- `ios/` — proyecto Xcode generado por Capacitor
- `.github/workflows/build-ios.yml` — workflow de build automático
