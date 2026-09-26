import XCTest
import CoreLocation
@testable import ActiveTransit

final class MockEnturNetworkClient: EnturClientProtocol {
    var mockedStops: [TransitStop] = []
    var mockedTrips: [TransitTrip] = []
    var shouldThrowError = false
    
    func fetchSubsequentStops(for serviceJourneyId: String) async throws -> [TransitStop] {
        if shouldThrowError {
            throw ActiveTransitError.invalidResponse
        }
        return mockedStops
    }
    
    func fetchNearestActiveServiceJourney(currentLocation: CLLocation) async throws -> String? {
        if shouldThrowError {
            throw ActiveTransitError.invalidResponse
        }
        return nil
    }
    
    func fetchTrips(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async throws -> [TransitTrip] {
        if shouldThrowError {
            throw ActiveTransitError.invalidResponse
        }
        return mockedTrips
    }
}

final class ActiveTransitTests: XCTestCase {
    
    func testRouterFindsOptimalStop() async throws {
        let mockNetwork = MockEnturNetworkClient()
        
        // Simulate stops ahead in time
        let now = Date()
        let stop1 = TransitStop(id: "1", name: "Stop 1", latitude: 59.911, longitude: 10.750, expectedArrivalTime: now.addingTimeInterval(300)) // 5 mins
        let stop2 = TransitStop(id: "2", name: "Stop 2", latitude: 59.915, longitude: 10.755, expectedArrivalTime: now.addingTimeInterval(600)) // 10 mins
        let stop3 = TransitStop(id: "3", name: "Stop 3", latitude: 59.920, longitude: 10.760, expectedArrivalTime: now.addingTimeInterval(900)) // 15 mins
        
        mockNetwork.mockedStops = [stop1, stop2, stop3]
        
        let router = ActiveTransitRouter(networkClient: mockNetwork, router: ActiveRouter())
        
        // User is at a specific location
        let currentPos = CLLocation(latitude: 59.912, longitude: 10.752)
        
        let optimalStop = try await router.findOptimalBoardingStop(
            for: "journey123",
            currentPosition: currentPos,
            walkingSpeed: 1.4,
            safetyMargin: 60 // 1 min safety
        )
        
        // Given distances, it should at least pick a valid stop.
        XCTAssertNotNil(optimalStop)
    }
    
    func testRouterThrowsErrorWhenNoStopIsReachable() async {
        let mockNetwork = MockEnturNetworkClient()
        
        // Simulate a stop that is too close in time but far in distance
        let now = Date()
        let stop1 = TransitStop(id: "1", name: "Stop 1", latitude: 60.0, longitude: 11.0, expectedArrivalTime: now.addingTimeInterval(10)) // 10 seconds away, impossible to walk
        
        mockNetwork.mockedStops = [stop1]
        let router = ActiveTransitRouter(networkClient: mockNetwork, router: ActiveRouter())
        let currentPos = CLLocation(latitude: 59.912, longitude: 10.752)
        
        do {
            _ = try await router.findOptimalBoardingStop(for: "journey123", currentPosition: currentPos)
            XCTFail("Should have thrown ActiveTransitError.noBetterStopFound")
        } catch let error as ActiveTransitError {
            if case .noBetterStopFound = error {
                // Success
            } else {
                XCTFail("Wrong error thrown: \(error)")
            }
        } catch {
            XCTFail("Wrong error thrown: \(error)")
        }
    }
    
    func testNetworkErrorPropagates() async {
        let mockNetwork = MockEnturNetworkClient()
        mockNetwork.shouldThrowError = true
        
        let router = ActiveTransitRouter(networkClient: mockNetwork, router: ActiveRouter())
        let currentPos = CLLocation(latitude: 59.912, longitude: 10.752)
        
        do {
            _ = try await router.findOptimalBoardingStop(for: "journey123", currentPosition: currentPos)
            XCTFail("Should have thrown error")
        } catch {
            // Expected
        }
    }
    
    // MARK: - Optimal Stop Selection
    
    func testRouterPicksFurthestReachableStop() async throws {
        let mockNetwork = MockEnturNetworkClient()
        let now = Date()
        
        // Three nearby stops with plenty of time — should pick the furthest reachable
        let stop1 = TransitStop(id: "A", name: "Nær", latitude: 59.9111, longitude: 10.7501, expectedArrivalTime: now.addingTimeInterval(600))
        let stop2 = TransitStop(id: "B", name: "Midt", latitude: 59.9115, longitude: 10.7510, expectedArrivalTime: now.addingTimeInterval(900))
        let stop3 = TransitStop(id: "C", name: "Langt", latitude: 59.9120, longitude: 10.7520, expectedArrivalTime: now.addingTimeInterval(1200))
        
        mockNetwork.mockedStops = [stop1, stop2, stop3]
        let router = ActiveTransitRouter(networkClient: mockNetwork, router: ActiveRouter())
        let currentPos = CLLocation(latitude: 59.911, longitude: 10.750)
        
        let optimal = try await router.findOptimalBoardingStop(
            stops: [stop1, stop2, stop3],
            currentPosition: currentPos,
            startTime: now,
            walkingSpeed: 1.4,
            safetyMargin: 60
        )
        
        // Should pick the furthest reachable stop (stop3), not the nearest
        XCTAssertEqual(optimal.id, "C", "Should pick the furthest reachable stop")
    }
    
    func testRouterHandlesEmptyStops() async {
        let mockNetwork = MockEnturNetworkClient()
        mockNetwork.mockedStops = []
        let router = ActiveTransitRouter(networkClient: mockNetwork, router: ActiveRouter())
        let currentPos = CLLocation(latitude: 59.912, longitude: 10.752)
        
        do {
            _ = try await router.findOptimalBoardingStop(for: "journey123", currentPosition: currentPos)
            XCTFail("Should have thrown invalidServiceJourney for empty stops")
        } catch let error as ActiveTransitError {
            if case .invalidServiceJourney = error {
                // Expected
            } else {
                XCTFail("Wrong error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    func testRouterSkipsAlreadyDepartedStops() async throws {
        let mockNetwork = MockEnturNetworkClient()
        let now = Date()
        
        // First two stops already departed, third is reachable
        let departedStop1 = TransitStop(id: "1", name: "Passed 1", latitude: 59.911, longitude: 10.750, expectedArrivalTime: now.addingTimeInterval(-60))
        let departedStop2 = TransitStop(id: "2", name: "Passed 2", latitude: 59.912, longitude: 10.751, expectedArrivalTime: now.addingTimeInterval(-10))
        let futureStop = TransitStop(id: "3", name: "Future", latitude: 59.913, longitude: 10.752, expectedArrivalTime: now.addingTimeInterval(600))
        
        mockNetwork.mockedStops = [departedStop1, departedStop2, futureStop]
        let router = ActiveTransitRouter(networkClient: mockNetwork, router: ActiveRouter())
        let currentPos = CLLocation(latitude: 59.912, longitude: 10.752)
        
        let optimal = try await router.findOptimalBoardingStop(
            stops: [departedStop1, departedStop2, futureStop],
            currentPosition: currentPos,
            startTime: now,
            walkingSpeed: 1.4,
            safetyMargin: 30
        )
        
        XCTAssertEqual(optimal.id, "3", "Should skip departed stops and pick the future one")
    }
    
    func testRouterHandlesLoopRoute() async throws {
        let now = Date()
        let currentPos = CLLocation(latitude: 59.912, longitude: 10.752)
        
        // Simulate a loop: stop2 is far away (unreachable), but stop3 comes back close (reachable)
        let stop1 = TransitStop(id: "1", name: "Close Start", latitude: 59.9121, longitude: 10.7521, expectedArrivalTime: now.addingTimeInterval(300))
        let stop2 = TransitStop(id: "2", name: "Far Loop", latitude: 60.0, longitude: 11.0, expectedArrivalTime: now.addingTimeInterval(600))
        let stop3 = TransitStop(id: "3", name: "Back Close", latitude: 59.9125, longitude: 10.7530, expectedArrivalTime: now.addingTimeInterval(900))
        
        let activeRouter = ActiveRouter()
        
        let optimal = try await activeRouter.calculateOptimalStop(
            currentPosition: currentPos,
            startTime: now,
            stops: [stop1, stop2, stop3],
            walkingSpeed: 1.4,
            safetyMargin: 60
        )
        
        // With the consecutive-miss buffer, it should still find stop3 even after stop2 is unreachable
        XCTAssertEqual(optimal.id, "3", "Should handle loop routes by looking past unreachable stops")
    }
    
    // MARK: - TransitTrip via Mock
    
    func testFetchTripsReturnsMockedData() async throws {
        let mockNetwork = MockEnturNetworkClient()
        let now = Date()
        
        let trip = TransitTrip(
            expectedStartTime: now,
            expectedEndTime: now.addingTimeInterval(1800),
            mainServiceJourneyId: "sj-1",
            description: "Trikk 11",
            mode: .tram,
            destinationName: "Majorstuen"
        )
        mockNetwork.mockedTrips = [trip]
        
        let router = ActiveTransitRouter(networkClient: mockNetwork, router: ActiveRouter())
        let trips = try await router.fetchTrips(
            from: CLLocationCoordinate2D(latitude: 59.91, longitude: 10.75),
            to: CLLocationCoordinate2D(latitude: 59.93, longitude: 10.77)
        )
        
        XCTAssertEqual(trips.count, 1)
        XCTAssertEqual(trips.first?.mainServiceJourneyId, "sj-1")
        XCTAssertEqual(trips.first?.mode, .tram)
    }
    
    // MARK: - TransitMode Decoding
    
    func testTransitModeDecodesKnownValues() throws {
        let decoder = JSONDecoder()
        
        let busJSON = Data("\"bus\"".utf8)
        let tramJSON = Data("\"tram\"".utf8)
        let metroJSON = Data("\"metro\"".utf8)
        
        XCTAssertEqual(try decoder.decode(TransitMode.self, from: busJSON), .bus)
        XCTAssertEqual(try decoder.decode(TransitMode.self, from: tramJSON), .tram)
        XCTAssertEqual(try decoder.decode(TransitMode.self, from: metroJSON), .metro)
    }
    
    func testTransitModeDecodesCaseInsensitive() throws {
        let decoder = JSONDecoder()
        
        let upperJSON = Data("\"BUS\"".utf8)
        let mixedJSON = Data("\"Tram\"".utf8)
        
        XCTAssertEqual(try decoder.decode(TransitMode.self, from: upperJSON), .bus)
        XCTAssertEqual(try decoder.decode(TransitMode.self, from: mixedJSON), .tram)
    }
    
    func testTransitModeDecodesUnknownAsUnknown() throws {
        let decoder = JSONDecoder()
        let unknownJSON = Data("\"helicopter\"".utf8)
        
        XCTAssertEqual(try decoder.decode(TransitMode.self, from: unknownJSON), .unknown)
    }
    
    func testTransitModeSafeRawValue() {
        XCTAssertEqual(TransitMode(safeRawValue: "RAIL"), .rail)
        XCTAssertEqual(TransitMode(safeRawValue: "Water"), .water)
        XCTAssertEqual(TransitMode(safeRawValue: "nonsense"), .unknown)
    }
}
