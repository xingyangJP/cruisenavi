import Foundation
import CoreLocation

/// A single timestamped, speed-tagged GPS sample captured during a ride.
/// Pure, Codable, device-free data carrier consumed by `RideIntegrityAnalyzer`.
struct RideLocationSample: Codable, Equatable, Sendable {
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let speedKmh: Double            // normalized (SpeedNormalizer output)
    let horizontalAccuracy: Double  // meters; negative => invalid fix

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// CoreMotion activity classification for a segment of ride time.
enum RideActivityKind: String, Codable, Sendable {
    case cycling, walking, running, automotive, stationary, unknown
}

/// A time interval tagged with a single activity kind, produced by `MotionActivityRecorder`.
struct RideActivitySegment: Codable, Equatable, Sendable {
    let startTime: Date
    let endTime: Date
    let kind: RideActivityKind
    let confidence: Int   // CMMotionActivityConfidence.rawValue: low=0, medium=1, high=2
}
