import Foundation
import CoreLocation

/// A network client that communicates with the Entur Journey Planner GraphQL API.
public final class EnturNetworkClient: EnturClientProtocol {
    private let clientName: String
    private let urlSession: URLSession
    private let endpointURL = URL(string: "https://api.entur.io/journey-planner/v3/graphql")!
    
    /// Initializes a new `EnturNetworkClient`.
    /// - Parameters:
    ///   - clientName: The `ET-Client-Name` header required by Entur (format: "company-application").
    ///   - urlSession: The `URLSession` to use for network requests. Defaults to `.shared`.
    public init(clientName: String, urlSession: URLSession = .shared) {
        self.clientName = clientName
        self.urlSession = urlSession
    }
    
    public func fetchSubsequentStops(for serviceJourneyId: String) async throws -> [TransitStop] {
        let query = """
        query getServiceJourney($id: String!) {
          serviceJourney(id: $id) {
            id
            estimatedCalls {
              expectedArrivalTime
              quay {
                id
                name
                latitude
                longitude
              }
            }
          }
        }
        """
        
        let variables: [String: Any] = ["id": serviceJourneyId]
        let requestBody: [String: Any] = [
            "query": query,
            "variables": variables
        ]
        
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue(clientName, forHTTPHeaderField: "ET-Client-Name")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            throw ActiveTransitError.networkError(error)
        }
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ActiveTransitError.invalidResponse
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let graphQLResponse: GraphQLResponse
        do {
            graphQLResponse = try decoder.decode(GraphQLResponse.self, from: data)
        } catch {
            throw ActiveTransitError.decodingError(error)
        }
        
        if let errors = graphQLResponse.errors, !errors.isEmpty {
            throw ActiveTransitError.graphQLError(errors.first?.message ?? "Unknown GraphQL Error")
        }
        
        guard let serviceJourney = graphQLResponse.data?.serviceJourney else {
            throw ActiveTransitError.invalidServiceJourney
        }
        
        // Map to Domain Models
        let stops = serviceJourney.estimatedCalls.compactMap { call -> TransitStop? in
            guard let expectedArrivalTime = call.expectedArrivalTime else { return nil }
            return TransitStop(
                id: call.quay.id,
                name: call.quay.name,
                latitude: call.quay.latitude,
                longitude: call.quay.longitude,
                expectedArrivalTime: expectedArrivalTime
            )
        }
        
        return stops
    }
    
    public func fetchNearestActiveServiceJourney(currentLocation: CLLocation) async throws -> String? {
        let query = """
        query nearestDeparture($lat: Float!, $lon: Float!) {
          nearest(latitude: $lat, longitude: $lon, maximumDistance: 500, filterByInUse: true, first: 1) {
            edges {
              node {
                place {
                  ... on StopPlace {
                    estimatedCalls(numberOfDepartures: 1) {
                      serviceJourney {
                        id
                      }
                    }
                  }
                }
              }
            }
          }
        }
        """
        
        let variables: [String: Any] = [
            "lat": currentLocation.coordinate.latitude,
            "lon": currentLocation.coordinate.longitude
        ]
        
        let requestBody: [String: Any] = [
            "query": query,
            "variables": variables
        ]
        
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue(clientName, forHTTPHeaderField: "ET-Client-Name")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            throw ActiveTransitError.networkError(error)
        }
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ActiveTransitError.invalidResponse
        }
        
        let decoder = JSONDecoder()
        
        let nearestResponse: NearestGraphQLResponse
        do {
            nearestResponse = try decoder.decode(NearestGraphQLResponse.self, from: data)
        } catch {
            throw ActiveTransitError.decodingError(error)
        }
        
        if let errors = nearestResponse.errors, !errors.isEmpty {
            throw ActiveTransitError.graphQLError(errors.first?.message ?? "Unknown GraphQL Error")
        }
        
        let edges = nearestResponse.data?.nearest?.edges ?? []
        for edge in edges {
            if let calls = edge.node.place.estimatedCalls, let firstCall = calls.first {
                return firstCall.serviceJourney.id
            }
        }
        
        return nil
    }
}

// MARK: - Internal DTOs

fileprivate struct GraphQLResponse: Codable {
    let data: GraphQLData?
    let errors: [GraphQLError]?
}

fileprivate struct GraphQLData: Codable {
    let serviceJourney: ServiceJourney?
}

// Nearest DTOs
fileprivate struct NearestGraphQLResponse: Codable {
    let data: NearestData?
    let errors: [GraphQLError]?
}

fileprivate struct NearestData: Codable {
    let nearest: NearestConnection?
}

fileprivate struct NearestConnection: Codable {
    let edges: [NearestEdge]
}

fileprivate struct NearestEdge: Codable {
    let node: NearestNode
}

fileprivate struct NearestNode: Codable {
    let place: NearestPlace
}

fileprivate struct NearestPlace: Codable {
    let estimatedCalls: [NearestEstimatedCall]?
}

fileprivate struct NearestEstimatedCall: Codable {
    let serviceJourney: NearestServiceJourney
}

fileprivate struct NearestServiceJourney: Codable {
    let id: String
}

fileprivate struct ServiceJourney: Codable {
    let id: String
    let estimatedCalls: [EstimatedCall]
}

fileprivate struct EstimatedCall: Codable {
    let expectedArrivalTime: Date?
    let quay: Quay
}

fileprivate struct Quay: Codable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
}

fileprivate struct GraphQLError: Codable {
    let message: String
}
