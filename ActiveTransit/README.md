# ActiveTransit Framework

`ActiveTransit` er et frittstående Swift-rammeverk designet for å muliggjøre **Aktiv Overgang** for tredjepartsapper innen kollektivtransport.

Biblioteket er bygget uten bindinger til spesifikke UI-rammeverk (som SwiftUI eller UIKit), slik at det enkelt kan importeres og brukes i eksisterende applikasjoner (for eksempel Ruter-appen).

## Kjernefunksjonalitet

1. **Entur API Integrasjon:**
   Inneholder en ferdigbygget GraphQL-klient (`EnturNetworkClient`) som kommuniserer med Entur Journey Planner v3. Den håndterer komplekse spørringer (som overgangen mellom transportdøgn og kalenderdøgn for natt-ruter) ut av boksen.
   
   **Reisesøket optimaliserer for tidligst ankomst, ikke minst mulig gange.** Brukeren går gjerne lenger til et fjernere stopp hvis det gir raskere reise, så søket sender:
   - `walkReluctance: 1.0` – étt minutt gange teller likt med étt minutt om bord (Entur-standard er 2.0, som straffer gange og skjuler raskere ruter med lengre gange).
   - `walkSpeed` – brukerens egen ganghastighet, slik at Entur vet hvilke fjerne stopp brukeren faktisk rekker.
   - `numTripPatterns: 8` – flere alternativer, sortert etter ankomsttid.
   
2. **Ruting og Aktiv Overgang:**
   Inneholder logikken for å ta en gitt transportrute (`serviceJourneyId`) og brukerens nåværende posisjon, for deretter å beregne hvilket stopp på ruten brukeren burde gå til for å korte ned ventetiden.
   
> **Merk om Omfang (Scope):** `ActiveRouter` jobber innenfor en *allerede valgt* rute. Valget av *hvilken* rute/linje (inkludert å gå til et fjernere stopp for å ta en raskere linje) gjøres av reisesøket hos Entur, som er konfigurert for tidligst ankomst (se over).

## Algoritmen (`ActiveRouter`)

**Mål:** Finn stoppet *lengst ut på ruten* (i kjøreretningen, mot avstigning) som brukeren rekker å gå til før transportmiddelet kommer. Siden man tar samme avgang, er ankomsttiden den samme – lengst ut på ruten betyr mest mulig gange uten å komme senere frem.

1. **Grovfiltrering (tapsfri):** Luftlinje er en nedre grense for gangavstand. Alle stopp som ikke kan nås selv i luftlinje forkastes. Ingen tidlig avbrudd, slik at ring-linjer som kommer tilbake nær brukeren håndteres.
2. **Rangering:** Kandidatene sorteres med stoppet lengst ut på ruten først.
3. **Presis verifisering:** De høyest rangerte kandidatene sjekkes med `preciseWalkTimeProvider` (f.eks. MapKit) i parallelle runder på 3, maks 6 oppslag totalt. Første kandidat (i rangert rekkefølge) som består, velges.
4. **Fallback:** Hvis et oppslag feiler (nettverk/rate limit) eller budsjettet er brukt opp, brukes et forsiktig estimat (luftlinje × 1.4). Et stopp som er **eksplisitt avvist** av presis gangtid returneres aldri.

> **Viktig:** `preciseWalkTimeProvider` må returnere gangtid basert på brukerens egen hastighet (f.eks. `route.distance / walkingSpeed`), ikke `MKRoute.expectedTravelTime`, som bruker Apples standardhastighet. Closuren er `@Sendable` fordi kandidatene sjekkes parallelt.

## Bruk

### Initialisering
```swift
import ActiveTransit

// Opprett en ruter-instans. Husk å bruke en unik ET-Client-Name header.
let router = ActiveTransitRouter(enturClientName: "ditt-firma-din-app")
```

### Beregne Optimalt Påstigningspunkt
Hvis du allerede har funnet en reise (f.eks. via din egen reiseplanlegger) og har hentet ut rutens stoppesteder, kan du bruke biblioteket slik:

```swift
let rutensStoppesteder: [TransitStop] = ... // Liste med stoppesteder

let optimaltStopp = try await router.findOptimalBoardingStop(
    stops: rutensStoppesteder,
    currentPosition: minLokasjon,
    startTime: Date(), // Tiden du starter å gå
    walkingSpeed: 1.4, // meter per sekund
    safetyMargin: 60, // 1 minutt sikkerhetsmargin
    preciseWalkTimeProvider: nil // Valgfritt: injiser presis gangtid (f.eks. MapKit-distanse / ganghastighet)
)

print("Du bør gå til: \(optimaltStopp.name)")
```

### Inkluderte Domenemodeller
- `TransitStop`: Representerer et stoppested med navn, koordinater og forventet ankomsttid for bussen.
- `TransitTrip`: Representerer en reise fra A til B (brukes av den innebygde reiseplanlegger-funksjonen).
- `TransitLeg`: Representerer en spesifikk etappe (f.eks. en T-bane-tur) med nøyaktige start- og slutt-tider, noe som løser disambiguering ved ring-linjer.
- `ActiveTransitError`: Omfattende error-handling for nettverksfeil, GraphQL-feil, og ruting-feil.

## Arkitektur
Modulen er bygget rundt protocols (`EnturClientProtocol` og `ActiveRoutingProtocol`). Dette betyr at du i din egen app enkelt kan bytte ut nettverksklienten med en mock-klient for Unit Testing av ditt eget UI, uten å måtte gjøre ekte kall mot Entur.
