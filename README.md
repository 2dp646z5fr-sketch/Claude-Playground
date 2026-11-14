# Rondjes – hardlooprondjes vanaf huis

iPhone-app (SwiftUI + Apple Kaarten) die vanaf je huis **81 hardlooprondjes** maakt:
van **3,0 km tot 43,0 km**, steeds **0,5 km** langer. Elk rondje start en eindigt bij je voordeur.

## Wat de app doet

- **Thuisadres instellen**: via je huidige locatie of door je adres te zoeken.
- **Routes maken**: per afstand rekent de app een rondgaande looproute uit via Apple Kaarten
  (te voet, geen API-sleutel nodig). Elke afstand krijgt standaard een andere richting,
  zodat je niet steeds dezelfde kant op loopt. Niet blij met een route? Tik op *Andere route*.
- **Alles in één keer**: *Genereer alle ontbrekende routes* maakt ze allemaal achter elkaar
  (Apple beperkt het aantal verzoeken per minuut, dus dit duurt even).
- **Voortgang**: vink rondjes af als gelopen; de app toont je volgende afstand en totaal aantal km.
- **GPX-export**: deel een route naar je Garmin/Coros/Strava/Komoot e.d. om onderweg te navigeren.
- Alles wordt lokaal op je telefoon bewaard.

## Hoe werkt het route-algoritme?

Er wordt een cirkel gelegd die door je huis loopt, met 4 tussenpunten op die cirkel.
Apple Kaarten berekent een looproute huis → P1 → P2 → P3 → P4 → huis. Daarna wordt de
straal van de cirkel bijgesteld tot de gerouteerde lengte binnen ±150 m van de doelafstand valt
(max. 6 pogingen; anders wordt de dichtstbijzijnde gebruikt – het verschil staat in de app).

## Op je iPhone zetten

Je hebt een Mac met **Xcode 15 of nieuwer** nodig (gratis Apple ID volstaat), of een iPad met **Swift Playgrounds**.

1. Clone deze repo en open de map **`Rondjes.swiftpm`** in Xcode (dubbelklik).
2. Sluit je iPhone aan (of kies hem via wifi) en selecteer hem als doel bovenin.
3. Bij *Signing & Capabilities* kies je je eigen team (je Apple ID).
4. Druk op ▶︎ Run. De eerste keer moet je op de iPhone de ontwikkelaar vertrouwen:
   *Instellingen › Algemeen › VPN en apparaatbeheer*.

Minimaal iOS 17.

## Bestanden

| Bestand | Inhoud |
|---|---|
| `Package.swift` | App-definitie (naam, icoon, locatietoestemming) |
| `LoopGenerator.swift` | Maakt een rondgaande route van de gewenste lengte |
| `LoopStore.swift` | Opslag, voortgang, batch-generatie, GPX-export |
| `ContentView.swift` | Overzicht met alle 81 afstanden |
| `LoopDetailView.swift` | Kaart met route, opnieuw genereren, afvinken, delen |
| `HomeSetupView.swift` | Thuisadres instellen |
