import Foundation

/// Centralized string constants for the app.
/// Prepares for future localization via String(localized:) or .strings files.
enum L10n {
    // MARK: - Onboarding
    enum Onboarding {
        static let welcomeTitle = String(localized: "Velkommen til\nActive Transit")
        static let welcomeSubtitle = String(localized: "Kollektiv-appen som hjelper deg å nå målet raskest mulig, samtidig som du får gått mest mulig.")
        static let walkingSpeedQuestion = String(localized: "Hvor raskt går du?")
        static let walkingSpeedExplanation = String(localized: "Dette brukes til å beregne hvor langt du rekker å gå før bussen kommer.")
        static let getStarted = String(localized: "Kom i gang")
        static let speedSlow = String(localized: "Rolig (1.0 m/s)")
        static let speedNormal = String(localized: "Normal (1.4 m/s)")
        static let speedFast = String(localized: "Rask (1.8 m/s)")
    }
    
    // MARK: - Trip Planner
    enum TripPlanner {
        static let title = String(localized: "Reiseplanlegger")
        static let searchPlaceholder = String(localized: "Søk etter sted eller adresse")
        static let tapMapPrompt = String(localized: "Trykk på kartet for å velge hvor du vil reise")
        static let searchDepartures = String(localized: "Søk etter avganger hit")
        static let searching = String(localized: "Søker i Entur...")
        static let selectDeparture = String(localized: "Velg avgang for Aktiv Overgang:")
        static let direct = String(localized: "Direkte")
        static let noRoutes = String(localized: "Fant ingen ruter.")
        static let missingPosition = String(localized: "Mangler din posisjon eller destinasjon.")
        static let unknownPlace = String(localized: "Ukjent sted")
        static let searchError = String(localized: "Klarte ikke å søke opp stedet.")
    }
    
    // MARK: - Map & Itinerary
    enum Map {
        static let calculatingRoute = String(localized: "Beregner rute...")
        static let destination = String(localized: "Destinasjon")
        static let activeTransfer = String(localized: "Aktiv Overgang")
        static let walkHere = String(localized: "Gå hit (Aktiv Overgang)")
        static let start = String(localized: "Start")
        static let transferHere = String(localized: "Bytt her")
        static let itinerary = String(localized: "Reiseplan")
        static let noItinerary = String(localized: "Ingen reiseplan")
        static let couldNotLoad = String(localized: "Kunne ikke laste inn ruten.")
        static let walkToDestination = String(localized: "Gå til destinasjonen")
        static let retry = String(localized: "Prøv igjen")
    }
    
    // MARK: - Settings
    enum Settings {
        static let title = String(localized: "Innstillinger")
        static let walkingSpeed = String(localized: "Gå-hastighet")
        static let safetyMargin = String(localized: "Sikkerhetsmargin")
        static let timeBeforeDeparture = String(localized: "Tid før avgang")
        static let done = String(localized: "Ferdig")
    }
    
    // MARK: - Errors
    enum Errors {
        static func fetchError(_ detail: String) -> String {
            String(localized: "Feil ved henting: \(detail)")
        }
        static func activeTransitError(_ detail: String) -> String {
            String(localized: "Feil med Aktiv Overgang: \(detail)")
        }
        static func unexpectedError(_ detail: String) -> String {
            String(localized: "En uventet feil oppstod: \(detail)")
        }
    }
    
    // MARK: - Accessibility
    enum A11y {
        static let settings = String(localized: "Innstillinger")
        static let retrySearch = String(localized: "Prøv søket på nytt")
        static let retryRoute = String(localized: "Prøv å laste ruten på nytt")
        static let loadingItinerary = String(localized: "Laster reiseplan")
        static func stopLabel(_ name: String) -> String {
            String(localized: "Stopp: \(name)")
        }
        static func startStop(_ name: String) -> String {
            String(localized: "Startstopp: \(name)")
        }
        static func transferAt(_ name: String) -> String {
            String(localized: "Bytt transport ved \(name)")
        }
        static func walkTo(_ name: String) -> String {
            String(localized: "Gå til \(name) for aktiv overgang")
        }
    }
}
