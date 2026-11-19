# CanonScan for Mac

App de macOS para escanear por WiFi con impresoras Canon PIXMA G3010 / G3110, que en macOS 26 ya no funcionan con el driver oficial.

macOS app to scan over Wi-Fi with Canon PIXMA G3010 / G3110 printers, which no longer work with the official driver on macOS 26.

[Español](#español) · [English](#english)

---

## Español

### Por qué

La G3010 / G3110 no ofrece escaneo AirPrint (eSCL) ni responde BJNP por la red. Escanea con **CHMP**, un protocolo de Canon sobre HTTP (puerto 80). CanonScan habla CHMP directamente: no necesita el driver de Canon, SANE, Python ni Homebrew.

### Funciones

- Busca la impresora sola por Bonjour, o usa una IP manual.
- 150, 300 o 600 dpi, en color o gris.
- Varias páginas en un solo PDF, con opción de reordenar y borrar.
- Guarda en PDF, JPG o PNG.
- Interfaz en español e inglés (según el idioma de macOS).
- App universal (Apple Silicon e Intel), macOS 13 o superior.

### Limitaciones

- Solo vidrio (sin alimentador), página A4 completa.
- Probado con una G3110 (se anuncia como «G3010 series»). Otros modelos con CHMP podrían funcionar, sin garantía.
- No es un driver oficial de Canon; el protocolo se obtuvo por ingeniería inversa.

### Instalar

Descarga `dist/CanonScan-1.0.pkg` e instálalo. El paquete no está firmado, así que abre con clic derecho → **Abrir**, o en Terminal:

```sh
sudo installer -pkg CanonScan-1.0.pkg -target /
```

La app queda en `/Applications/CanonScan.app`. Al primer escaneo macOS pide permiso de **Red local**: acéptalo.

### Compilar

Requiere Xcode (Swift 5.9 o superior).

```sh
./build.sh      # solo la app, en build/latest/
./package.sh    # app + instalador en dist/
```

### Créditos

El cliente CHMP está portado a Swift desde [dfrancio-DF/canon-g3010-sane](https://github.com/dfrancio-DF/canon-g3010-sane), derivado de [wailun42/canon-g3010-chmp-scanner](https://github.com/wailun42/canon-g3010-chmp-scanner). Ver [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

---

## English

### Why

The G3010 / G3110 offers no AirPrint scanning (eSCL) and doesn't answer BJNP on the network. It scans with **CHMP**, a Canon protocol over HTTP (port 80). CanonScan speaks CHMP directly: no Canon driver, SANE, Python or Homebrew needed.

### Features

- Finds the printer automatically via Bonjour, or uses a manual IP.
- 150, 300 or 600 dpi, color or gray.
- Multiple pages in one PDF, with reordering and deleting.
- Saves as PDF, JPG or PNG.
- Spanish and English interface (follows the macOS language).
- Universal app (Apple Silicon and Intel), macOS 13 or later.

### Limitations

- Flatbed only (no feeder), full A4 page.
- Tested with a G3110 (it advertises itself as "G3010 series"). Other CHMP models may work, no guarantee.
- Not an official Canon driver; the protocol was reverse-engineered.

### Install

Download `dist/CanonScan-1.0.pkg` and install it. The package is unsigned, so open it with right-click → **Open**, or in Terminal:

```sh
sudo installer -pkg CanonScan-1.0.pkg -target /
```

The app goes to `/Applications/CanonScan.app`. On the first scan macOS asks for **Local Network** permission: allow it.

### Build

Requires Xcode (Swift 5.9 or later).

```sh
./build.sh      # app only, in build/latest/
./package.sh    # app + installer in dist/
```

### Credits

The CHMP client is ported to Swift from [dfrancio-DF/canon-g3010-sane](https://github.com/dfrancio-DF/canon-g3010-sane), derived from [wailun42/canon-g3010-chmp-scanner](https://github.com/wailun42/canon-g3010-chmp-scanner). See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

---

Canon y PIXMA son marcas de Canon Inc. Este proyecto no está afiliado a Canon.
Canon and PIXMA are trademarks of Canon Inc. This project is not affiliated with Canon.
