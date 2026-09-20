# Kollektivtransport & Aktiv Overgang 🚌🚶‍♂️

Dette prosjektet er en komplett iOS-applikasjon og tilhørende rammeverk for **Aktiv Overgang**. 

*Aktiv Overgang* er et konsept for kollektivtrafikken hvor brukerne, i stedet for å stå passivt og vente på et stoppested, får et forslag om å spasere til et stoppested lenger frem på ruten for å korte ned ventetiden, få mosjon og unngå kalde holdeplasser — uten å miste avgangen sin.

### Aktiv Overgang vs. Kryss-rute Optimalisering
Viktig å bemerke: Dette rammeverket er et "mikro-optimaliseringsverktøy" for *etter* at du har valgt en spesifikk reise. 
* **Kryss-rute optimalisering** (å sjekke om det er raskere å gå til et helt annet stopp for å ta en annen rute) håndteres av selve **Reiseplanleggeren** (Entur) når du gjør det opprinnelige søket fra A til B. Hvis det er raskere å gå 10 minutter for å ta en annen bane, vil Entur foreslå dette som det beste reisealternativet.
* **Aktiv Overgang** (dette prosjektet) trer i kraft *etter* at du har valgt ruten din, og hjelper deg med å holde deg i bevegelse langs den valgte ruten frem til transportmiddelet plukker deg opp.

## Prosjektstruktur

Prosjektet består av to hoveddeler:

1. **`ActiveTransit` (Swift Package):** 
   Dette er selve hjernen i systemet. Det er et frittstående, modulært rammeverk som håndterer all forretningslogikk.
   - Snakker med **Entur GraphQL API** for å hente ruter, stopp og sanntidsdata.
   - Inneholder algoritmen som beregner optimalt gå-stopp basert på brukerens nåværende posisjon, gangfart og en sikkerhetsmargin.
   
2. **`KollektivApp` (iOS App):**
   Dette er en SwiftUI-basert iOS-app som demonstrerer rammeverket i praksis.
   - **`TripPlannerView`**: Lar brukeren velge en destinasjon på kartet og søke opp neste avganger (mini-reiseplanlegger).
   - **`TransitMapView`**: Tegner opp hele ruten til den valgte avgangen på et kart, og plasserer en egen, grønn markør på det stoppet du bør begynne å gå mot.

## Kom i gang

### Krav
- **Xcode 15.0+**
- **iOS 17.0+** (Appen bruker moderne MapKit-syntaks fra iOS 17)
- **Swift 5.9+**

### Hvordan bygge og kjøre
1. Åpne `KollektivApp.xcodeproj` i Xcode.
2. Sørg for at den lokale pakken `ActiveTransit` er lastet inn riktig (ligger under "Package Dependencies" i venstremenyen).
3. Velg en iOS 17-simulator (eller din egen iPhone).
4. Trykk **Cmd + R** for å bygge appen.

> **Viktig for testing i simulator:**
> Appen krever posisjonsdata for å beregne gå-avstander. I iOS-simulatoren må du gå til menylinjen:
> `Features -> Location -> Custom Location...` og skrive inn en gyldig Oslo-koordinat (f.eks. Latitude: 59.911491, Longitude: 10.757933 for Jernbanetorget).

## Arkitektur

Prosjektet er bygget med Protocol-Oriented Programming (POP) for å gjøre det enkelt å teste og utvide:
- `EnturClientProtocol`: Håndterer nettverkskall mot Entur.
- `ActiveRoutingProtocol`: Håndterer avstand- og tidsberegninger (kan utvides til å bruke Apple Maps via `MKDirections` for presis gangtid).
- `ActiveTransitRouter`: En fasade (Facade pattern) som kombinerer nettverk og ruting, og er det eneste kontaktpunktet appen trenger.

## Veien Videre
- Integrere `MKDirections` for nøyaktig gangtid i stedet for fugleperspektiv (Haversine).
- Legge til støtte for push-varsler ("Du må begynne å gå nå for å rekke trikken på neste stopp").
- Støtte for flere transportmidler (tog, ferge).
