# Rondjes – hardlooprondjes vanaf huis

## Webversie (aanbevolen)

Open in Safari op je iPhone of iPad en kies *Deel → Zet op beginscherm*:
https://raw.githack.com/2dp646z5fr-sketch/Claude-Playground/claude/determined-wright-3o359x/docs/index.html

- Kies een afstand in de lijst (standaard 3–43 km per 0,5 km, aan te passen) of typ zelf een afstand in.
- Routes gaan zoveel mogelijk door natuur en buiten de bebouwde kom: de app leest het landschap rond je huis af
  van de OpenStreetMap-kaart (woonwijk, bos, weiland, water), kiest de groenste richting en plant via BRouter met
  een eigen natuurprofiel (paden voorrang, drukke wegen vermeden).
- Per route: percentage natuur en bebouwd, looptijd op jouw tempo, hoogteprofiel, GPX-export, afvinken.

Broncode: `docs/index.html`.

## Native iPhone/iPad-app (SwiftUI, versie 2)

`Rondjes.swiftpm` is de native versie met dezelfde functies als de webversie:
natuurroutes via BRouter + landschapsanalyse van de OpenStreetMap-kaart, eigen afstanden,
instelbare reeks en tempo, voortgang, hoogteprofiel en GPX-export. Vereist iOS/iPadOS 17.

**Openen op iPad:** zet de map `Rondjes.swiftpm` (of de zip) in Bestanden en open hem met
Swift Playgrounds. Druk op ▶︎.
**Openen op Mac:** dubbelklik `Rondjes.swiftpm` om hem in Xcode te openen, kies je iPhone en druk op Run.

| Bestand | Inhoud |
|---|---|
| `Package.swift` | App-definitie (naam, icoon, locatietoestemming, iPhone + iPad) |
| `Theme.swift` | Kleuren (licht/donker), lettertypes en knopstijlen |
| `Models.swift` | Route, reeks, notatie van getallen |
| `Geo.swift` | Geometrie en polyline-codering |
| `Router.swift` | BRouter met natuurprofiel, gewone looproute als reserve |
| `LandCover.swift` | Leest bebouwing/natuur uit OpenStreetMap-kaarttegels |
| `LoopGenerator.swift` | Kiest de groenste richting en stemt de lengte af |
| `LoopStore.swift` | Opslag, voortgang, alle routes maken, GPX |
| `ContentView.swift` | Hoofdscherm, kaart en bovenbalk |
| `RouteCard.swift` | Routekaart met natuurbalk, statistieken en hoogteprofiel |
| `PickerAndProgress.swift` | Afstand invullen, voortgangsring, overzicht per 5 km |
| `HomeSetupView.swift` / `SettingsView.swift` | Thuisadres en instellingen |
