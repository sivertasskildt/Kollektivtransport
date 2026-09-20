import XCTest
import CoreLocation
@testable import ActiveTransit

final class MockEnturNetworkClient: EnturClientProtocol {
    var mockedStops: [TransitStop] = []
    var shouldThrowError = false
    
    func fetchSubsequentStops(for serviceJourneyId: String) async throws -> [TransitStop] {
        if shouldThrowError {
            throw ActiveTransitError.invalidResponse
        }
        return mockedStops
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
}
