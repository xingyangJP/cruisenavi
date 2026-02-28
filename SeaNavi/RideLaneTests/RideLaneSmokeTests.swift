import XCTest
import CoreLocation
@testable import RideLane

final class RideLaneSmokeTests: XCTestCase {
    func testSmoke() {
        XCTAssertTrue(true)
    }

    func testSpeedNormalizerUsesFreshGPSSpeed() {
        let now = Date()
        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 35.0, longitude: 139.0),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: -1,
            speed: 5.0,
            timestamp: now
        )

        let result = SpeedNormalizer.normalizedSpeed(
            currentSpeedKmh: 0,
            location: location,
            lastSampleLocation: nil,
            now: now
        )

        XCTAssertEqual(result.speedKmh, 6.3, accuracy: 0.01)
        XCTAssertNil(result.fallbackKmhUsed)
    }

    func testSpeedNormalizerFallsBackToDistanceOverTimeWhenGPSIsInvalid() {
        let now = Date()
        let previous = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 35.0, longitude: 139.0),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: -1,
            speed: 0,
            timestamp: now.addingTimeInterval(-4)
        )
        let current = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 35.0, longitude: 139.0007904),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: -1,
            speed: -1,
            timestamp: now
        )

        let result = SpeedNormalizer.normalizedSpeed(
            currentSpeedKmh: 0,
            location: current,
            lastSampleLocation: previous,
            now: now
        )
        let expectedFallbackKmh = (current.distance(from: previous) / 4.0) * 3.6
        let expectedSmoothed = expectedFallbackKmh * 0.35

        XCTAssertNotNil(result.fallbackKmhUsed)
        XCTAssertEqual(result.speedKmh, expectedSmoothed, accuracy: 0.01)
    }

    func testSpeedNormalizerConvergesToZeroAtStopThreshold() {
        let now = Date()
        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 35.0, longitude: 139.0),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: -1,
            speed: 0.1,
            timestamp: now
        )

        let result = SpeedNormalizer.normalizedSpeed(
            currentSpeedKmh: 1.0,
            location: location,
            lastSampleLocation: nil,
            now: now
        )

        XCTAssertEqual(result.speedKmh, 0, accuracy: 0.0001)
    }

    func testRouteProgressEstimatorDropsPassedCoordinates() {
        let route = [
            CLLocationCoordinate2D(latitude: 35.0000, longitude: 139.0000),
            CLLocationCoordinate2D(latitude: 35.0000, longitude: 139.0010),
            CLLocationCoordinate2D(latitude: 35.0000, longitude: 139.0020)
        ]
        let current = CLLocationCoordinate2D(latitude: 35.0000, longitude: 139.0012)

        let update = RouteProgressEstimator.remainingProgress(
            currentCoordinate: current,
            route: route
        )

        let totalKm = RouteProgressEstimator.pathDistanceMeters(of: route) / 1000.0
        guard let firstRemaining = update.remainingRoute.first else {
            XCTFail("remaining route is empty")
            return
        }
        XCTAssertEqual(update.remainingRoute.count, 2)
        XCTAssertEqual(firstRemaining.longitude, route[1].longitude, accuracy: 0.000001)
        XCTAssertGreaterThan(update.remainingDistanceKm, 0)
        XCTAssertLessThan(update.remainingDistanceKm, totalKm)
    }

    func testRouteGeometryDistanceNearRouteIsSmall() {
        let route = [
            CLLocationCoordinate2D(latitude: 35.0, longitude: 139.0),
            CLLocationCoordinate2D(latitude: 35.0, longitude: 139.01)
        ]
        let pointOnRoute = CLLocationCoordinate2D(latitude: 35.0, longitude: 139.005)

        let distance = RouteGeometry.distanceFromRoute(pointOnRoute, route: route)

        XCTAssertLessThan(distance, 1.0)
    }

    func testRouteGeometryDistanceOffRouteMatchesApproxMeters() {
        let route = [
            CLLocationCoordinate2D(latitude: 35.0, longitude: 139.0),
            CLLocationCoordinate2D(latitude: 35.0, longitude: 139.01)
        ]
        let offRoutePoint = CLLocationCoordinate2D(latitude: 35.001, longitude: 139.005)

        let distance = RouteGeometry.distanceFromRoute(offRoutePoint, route: route)

        XCTAssertGreaterThan(distance, 90)
        XCTAssertLessThan(distance, 130)
    }
}
