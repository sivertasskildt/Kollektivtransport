import Foundation

/// Errors that can occur within the ActiveTransit framework.
public enum ActiveTransitError: Error, LocalizedError {
    /// Network-related errors.
    case networkError(Error)
    
    /// Server returned an invalid response or status code.
    case invalidResponse
    
    /// Failed to decode the response data.
    case decodingError(Error)
    
    /// The GraphQL request returned an error.
    case graphQLError(String)
    
    /// Missing or invalid data for the requested service journey.
    case invalidServiceJourney
    
    /// Could not find a better stop (e.g. the bus has already passed or you can't walk fast enough).
    case noBetterStopFound
    
    public var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error occurred: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from the server."
        case .decodingError(let error):
            return "Failed to decode server response: \(error.localizedDescription)"
        case .graphQLError(let message):
            return "GraphQL Error: \(message)"
        case .invalidServiceJourney:
            return "Invalid service journey data received."
        case .noBetterStopFound:
            return "Could not find a better stop to walk to."
        }
    }
}
