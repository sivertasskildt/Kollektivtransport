# ActiveTransit Framework

`ActiveTransit` er et frittstående Swift-rammeverk designet for å muliggjøre **Aktiv Overgang** for tredjepartsapper innen kollektivtransport.

Biblioteket er bygget uten bindinger til spesifikke UI-rammeverk (som SwiftUI eller UIKit), slik at det enkelt kan importeres og brukes i eksisterende applikasjoner (for eksempel Ruter-appen).

## Kjernefunksjonalitet

1. **Entur API Integrasjon:**
   Inneholder en ferdigbygget GraphQL-klient (`EnturNetworkClient`) som kommuniserer med Entur Journey Planner v3. Den håndterer komplekse spørringer (som overgangen mellom transportdøgn og kalenderdøgn for natt-ruter) ut av boksen.
   
2. **Ruting og Aktiv Overgang:**
   Inneholder logikken for å ta en gitt transportrute (`serviceJourneyId`) og brukerens nåværende posisjon, for deretter å beregne hvilket stopp på ruten brukeren burde gå til for å korte ned ventetiden.
   
> **Merk om Omfang (Scope):** ActiveTransit-rammeverket er bygget spesifikt for en *allerede valgt* rute. Det utfører **ikke** Multi-Modal kryss-rute optimalisering (f.eks. å finne ut at det er raskere å gå til et annet stopp for å ta en *annen* bane). Slik optimalisering gjøres av det underliggende reiseplanlegger-søket (hos Entur) før denne modulen aktiveres.

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
    preciseWalkTimeProvider: nil // Valgfritt: injiser Apple Maps ETA her
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
