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
        query getServiceJourney($id: String!, $today: Date, $yesterday: Date) {
          serviceJourney(id: $id) {
            id
            callsToday: estimatedCalls(date: $today) {
              expectedArrivalTime
              quay { id name latitude longitude }
            }
            callsYesterday: estimatedCalls(date: $yesterday) {
              expectedArrivalTime
              quay { id name latitude longitude }
            }
          }
        }
        """
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        let todayStr = formatter.string(from: Date())
        let yesterdayStr = formatter.string(from: Date().addingTimeInterval(-86400))
        
        let variables: [String: Any] = [
            "id": serviceJourneyId,
            "today": todayStr,
            "yesterday": yesterdayStr
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
        
        // Plukk den listen som faktisk har data (løser natt-ruter problemet)
        let calls = (serviceJourney.callsToday ?? []).isEmpty ? (serviceJourney.callsYesterday ?? []) : (serviceJourney.callsToday ?? [])
        
        if calls.isEmpty {
            throw ActiveTransitError.invalidServiceJourney
        }
        
        // Map to Domain Models
        let stops = calls.compactMap { call -> TransitStop? in
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
    
    public func fetchTrips(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async throws -> [TransitTrip] {
        let query = """
        query getTrip($fromLat: Float!, $fromLon: Float!, $toLat: Float!, $toLon: Float!) {
          trip(
            from: {coordinates: {latitude: $fromLat, longitude: $fromLon}}
            to: {coordinates: {latitude: $toLat, longitude: $toLon}}
            numTripPatterns: 5
          ) {
            tripPatterns {
              expectedStartTime
              expectedEndTime
              legs {
                mode
                line {
                  publicCode
                  name
                }
                serviceJourney {
                  id
                }
              }
            }
          }
        }
        """
        
        let variables: [String: Any] = [
            "fromLat": from.latitude,
            "fromLon": from.longitude,
            "toLat": to.latitude,
            "toLon": to.longitude
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
        decoder.dateDecodingStrategy = .iso8601
        
        let tripResponse: TripGraphQLResponse
        do {
            tripResponse = try decoder.decode(TripGraphQLResponse.self, from: data)
        } catch {
            throw ActiveTransitError.decodingError(error)
        }
        
        if let errors = tripResponse.errors, !errors.isEmpty {
            throw ActiveTransitError.graphQLError(errors.first?.message ?? "Unknown GraphQL Error")
        }
        
        let patterns = tripResponse.data?.trip?.tripPatterns ?? []
        
        var trips: [TransitTrip] = []
        for pattern in patterns {
            // Find the first transit leg (not foot)
            guard let transitLeg = pattern.legs.first(where: { $0.mode != "foot" && $0.serviceJourney != nil }),
                  let serviceJourneyId = transitLeg.serviceJourney?.id else {
                continue
            }
            
            let lineName = transitLeg.line?.publicCode ?? transitLeg.line?.name ?? "Transport"
            let desc = "\(lineName)"
            
            let trip = TransitTrip(
                expectedStartTime: pattern.expectedStartTime,
                expectedEndTime: pattern.expectedEndTime,
                mainServiceJourneyId: serviceJourneyId,
                description: desc
            )
            trips.append(trip)
        }
        
        return trips
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
    let callsToday: [EstimatedCall]?
    let callsYesterday: [EstimatedCall]?
}

// Trip DTOs
fileprivate struct TripGraphQLResponse: Codable {
    let data: TripData?
    let errors: [GraphQLError]?
}

fileprivate struct TripData: Codable {
    let trip: TripConnection?
}

fileprivate struct TripConnection: Codable {
    let tripPatterns: [TripPattern]
}

fileprivate struct TripPattern: Codable {
    let expectedStartTime: Date
    let expectedEndTime: Date
    let legs: [TripLeg]
}

fileprivate struct TripLeg: Codable {
    let mode: String
    let line: TripLine?
    let serviceJourney: TripServiceJourney?
}

fileprivate struct TripLine: Codable {
    let publicCode: String?
    let name: String?
}

fileprivate struct TripServiceJourney: Codable {
    let id: String
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
