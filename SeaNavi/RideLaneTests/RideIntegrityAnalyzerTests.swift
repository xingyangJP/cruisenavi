import XCTest
import CoreLocation
@testable import RideLane

final class RideIntegrityAnalyzerTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    /// Straight east-bound track; each successive point is `stepMeters` further east.
    /// Longitude delta for a given eastward distance at latitude 35 deg.
    private func lon(east meters: Double) -> Double {
        let metersPerDegLon = 111_320.0 * cos(35.0 * .pi / 180.0)
        return 139.0 + meters / metersPerDegLon
    }

    private func sample(
        secondsFromStart: TimeInterval,
        eastMeters: Double,
        speedKmh: Double,
        accuracy: Double = 5
    ) -> RideLocationSample {
        RideLocationSample(
            timestamp: base.addingTimeInterval(secondsFromStart),
            latitude: 35.0,
            longitude: lon(east: eastMeters),
            speedKmh: speedKmh,
            horizontalAccuracy: accuracy
        )
    }

    func testSpikeIsRejectedSustainedValueWins() {
        // 20 km/h sustained with a single 1-sample 80 km/h spike in the middle.
        let speeds: [Double] = [20, 20, 80, 20, 20, 20]
        let samples = speeds.enumerated().map { index, speed in
            sample(secondsFromStart: Double(index), eastMeters: Double(index) * 6, speedKmh: speed)
        }
        let result = RideIntegrityAnalyzer.analyze(samples: samples, segments: [])
        // Window minimum kills the spike; sustained value is ~20.
        XCTAssertEqual(result.maxSustainedSpeed, 20, accuracy: 0.5)
        XCTAssertLessThan(result.maxSustainedSpeed, 80)
    }

    func testGenuineSustainedRunIsRecorded() {
        // Steady 40 km/h for 6 seconds (7 samples spanning 6s >= 3s window).
        let samples = (0...6).map { index in
            sample(secondsFromStart: Double(index), eastMeters: Double(index) * 11, speedKmh: 40)
        }
        let result = RideIntegrityAnalyzer.analyze(samples: samples, segments: [])
        XCTAssertEqual(result.maxSustainedSpeed, 40, accuracy: 0.5)
    }

    func testSustainedSpeedWithJitteryTimestamps() {
        // Regression for the window-boundary bug: real GPS timestamps are sub-second and never
        // land exactly at `window` seconds. A steady 40 km/h run with non-integer offsets must
        // still register a nonzero sustained speed (previously returned 0).
        let offsets: [TimeInterval] = [0.0, 0.98, 2.03, 3.12, 4.05, 5.11, 6.0]
        let samples = offsets.enumerated().map { index, offset in
            sample(secondsFromStart: offset, eastMeters: Double(index) * 11, speedKmh: 40)
        }
        let result = RideIntegrityAnalyzer.analyze(samples: samples, segments: [])
        XCTAssertEqual(result.maxSustainedSpeed, 40, accuracy: 0.5)
        XCTAssertGreaterThan(result.maxSustainedSpeed, 0)
    }

    func testShortHighSpeedBurstIsKept() {
        // §4.2 (loosened): a 6-second 60 km/h burst with no motion data (`.unknown`) is a
        // plausible descent, NOT vehicle evidence. Only sustained cruising is excluded.
        let samples = (0...6).map { index in
            sample(secondsFromStart: Double(index), eastMeters: Double(index) * 17, speedKmh: 60)
        }
        let result = RideIntegrityAnalyzer.analyze(samples: samples, segments: [])
        XCTAssertEqual(result.validSampleRatio, 1.0, accuracy: 0.0001)
        XCTAssertEqual(result.maxSustainedSpeed, 60, accuracy: 0.5)
        XCTAssertTrue(result.isRankingEligible)
    }

    func testSustainedVehicleCruiseExcluded() {
        // 120 seconds continuously above 50 km/h with no `.cycling` confirmation reads as vehicle
        // travel: cars hold that for minutes, a bike cannot without a confirmed descent.
        let samples = (0...120).map { index in
            sample(secondsFromStart: Double(index), eastMeters: Double(index) * 17, speedKmh: 60)
        }
        let result = RideIntegrityAnalyzer.analyze(samples: samples, segments: [])
        XCTAssertEqual(result.validSampleRatio, 0, accuracy: 0.0001)
        XCTAssertEqual(result.maxSustainedSpeed, 0, accuracy: 0.0001)
        XCTAssertFalse(result.isRankingEligible)
    }

    func testSustainedCruiseConfirmedCyclingIsKept() {
        // The same 120-second 60 km/h run under a `.cycling` segment (long confirmed descent)
        // must stay valid — CoreMotion's positive confirmation overrides the cruise rule.
        let samples = (0...120).map { index in
            sample(secondsFromStart: Double(index), eastMeters: Double(index) * 17, speedKmh: 60)
        }
        let segments = [
            RideActivitySegment(startTime: base, endTime: base.addingTimeInterval(130), kind: .cycling, confidence: 2)
        ]
        let result = RideIntegrityAnalyzer.analyze(samples: samples, segments: segments)
        XCTAssertEqual(result.validSampleRatio, 1.0, accuracy: 0.0001)
        XCTAssertTrue(result.isRankingEligible)
    }

    func testHighSpeedConfirmedCyclingIsKept() {
        // The vehicle-cruise rule must NOT punish a genuine fast descent that CoreMotion confirms
        // as cycling: 60 km/h under a `.cycling` segment stays valid and eligible.
        let samples = (0...6).map { index in
            sample(secondsFromStart: Double(index), eastMeters: Double(index) * 17, speedKmh: 60)
        }
        let segments = [
            RideActivitySegment(startTime: base, endTime: base.addingTimeInterval(20), kind: .cycling, confidence: 2)
        ]
        let result = RideIntegrityAnalyzer.analyze(samples: samples, segments: segments)
        XCTAssertEqual(result.validSampleRatio, 1.0, accuracy: 0.0001)
        XCTAssertEqual(result.maxSustainedSpeed, 60, accuracy: 0.5)
        XCTAssertTrue(result.isRankingEligible)
    }

    func testTooShortRideHasZeroSustainedSpeed() {
        // Three samples spanning only 2 seconds (< 3s window).
        let samples = [
            sample(secondsFromStart: 0, eastMeters: 0, speedKmh: 30),
            sample(secondsFromStart: 1, eastMeters: 8, speedKmh: 30),
            sample(secondsFromStart: 2, eastMeters: 16, speedKmh: 30)
        ]
        let result = RideIntegrityAnalyzer.analyze(samples: samples, segments: [])
        XCTAssertEqual(result.maxSustainedSpeed, 0, accuracy: 0.0001)
    }

    func testAutomotiveLabelAtBikeSpeedIsKept() {
        // Handlebar-mounted phones systematically classify a genuine ride as `.automotive`
        // (no pedaling body motion reaches the accelerometer). The label alone must NOT
        // invalidate bike-plausible samples: 25 km/h under an automotive segment stays valid.
        let samples = (0..<10).map { index in
            sample(secondsFromStart: Double(index), eastMeters: Double(index) * 10, speedKmh: 25)
        }
        let segments = [
            RideActivitySegment(startTime: base, endTime: base.addingTimeInterval(5), kind: .cycling, confidence: 2),
            RideActivitySegment(startTime: base.addingTimeInterval(5), endTime: base.addingTimeInterval(20), kind: .automotive, confidence: 2)
        ]
        let result = RideIntegrityAnalyzer.analyze(samples: samples, segments: segments)
        XCTAssertEqual(result.validSampleRatio, 1.0, accuracy: 0.0001)
        XCTAssertEqual(result.maxSustainedSpeed, 25, accuracy: 0.5)
        XCTAssertTrue(result.isRankingEligible)
        // The breakdown still records what CoreMotion reported, for display and future tuning.
        XCTAssertEqual(result.activityBreakdown[RideActivityKind.automotive.rawValue] ?? 0, 0.5, accuracy: 0.1)
    }

    func testAutomotiveSustainedCruiseExcluded() {
        // Automotive label + sustained 60 km/h cruising for 2 minutes: this is corroborated
        // vehicle travel and must be excluded (the real anti-cheat case — driving a car).
        let samples = (0...120).map { index in
            sample(secondsFromStart: Double(index), eastMeters: Double(index) * 17, speedKmh: 60)
        }
        let segments = [
            RideActivitySegment(startTime: base, endTime: base.addingTimeInterval(130), kind: .automotive, confidence: 2)
        ]
        let result = RideIntegrityAnalyzer.analyze(samples: samples, segments: segments)
        XCTAssertEqual(result.validSampleRatio, 0, accuracy: 0.0001)
        XCTAssertFalse(result.isRankingEligible)
    }

    func testSanityCapExcludesImplausibleSample() {
        // 5 valid at 30 km/h, one at 120 km/h (invalid).
        let speeds: [Double] = [30, 30, 30, 120, 30, 30]
        let samples = speeds.enumerated().map { index, speed in
            sample(secondsFromStart: Double(index), eastMeters: Double(index) * 8, speedKmh: speed)
        }
        let result = RideIntegrityAnalyzer.analyze(samples: samples, segments: [])
        XCTAssertEqual(result.validSampleRatio, 5.0 / 6.0, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(result.maxSustainedSpeed, 90)
    }

    func testEligibleWhenRatioAboveThreshold() {
        let samples = (0...5).map { index in
            sample(secondsFromStart: Double(index), eastMeters: Double(index) * 8, speedKmh: 28)
        }
        let result = RideIntegrityAnalyzer.analyze(samples: samples, segments: [])
        XCTAssertEqual(result.validSampleRatio, 1.0, accuracy: 0.0001)
        XCTAssertTrue(result.isRankingEligible)
    }

    func testMountedPhoneMisclassificationStaysEligible() {
        // Regression for the 2026-07-20 field ride: 89% of a genuine 18.7 km/h average ride was
        // labelled `.automotive` by CoreMotion (handlebar mount) and the whole ride was excluded.
        // At bike-plausible speeds the label must not affect eligibility.
        let samples = (0..<10).map { index in
            sample(secondsFromStart: Double(index), eastMeters: Double(index) * 10, speedKmh: 25)
        }
        let segments = [
            RideActivitySegment(startTime: base, endTime: base.addingTimeInterval(1), kind: .cycling, confidence: 2),
            RideActivitySegment(startTime: base.addingTimeInterval(1), endTime: base.addingTimeInterval(20), kind: .automotive, confidence: 2)
        ]
        let result = RideIntegrityAnalyzer.analyze(samples: samples, segments: segments)
        XCTAssertEqual(result.validSampleRatio, 1.0, accuracy: 0.0001)
        XCTAssertTrue(result.isRankingEligible)
    }

    func testEmptySamplesReturnsZeroResult() {
        let result = RideIntegrityAnalyzer.analyze(samples: [], segments: [])
        XCTAssertEqual(result.maxSustainedSpeed, 0)
        XCTAssertEqual(result.effectiveDistance, 0)
        XCTAssertEqual(result.validSampleRatio, 0)
        XCTAssertFalse(result.isRankingEligible)
        XCTAssertTrue(result.activityBreakdown.isEmpty)
    }

    func testActivityBreakdownFractionsSumToOne() {
        // 10s ride: cycling for first 6s, automotive for last 4s.
        let samples = (0...10).map { index in
            sample(secondsFromStart: Double(index), eastMeters: Double(index) * 5, speedKmh: 20)
        }
        let segments = [
            RideActivitySegment(startTime: base, endTime: base.addingTimeInterval(6), kind: .cycling, confidence: 2),
            RideActivitySegment(startTime: base.addingTimeInterval(6), endTime: base.addingTimeInterval(10), kind: .automotive, confidence: 2)
        ]
        let result = RideIntegrityAnalyzer.analyze(samples: samples, segments: segments)
        let total = result.activityBreakdown.values.reduce(0, +)
        XCTAssertEqual(total, 1.0, accuracy: 0.05)
        XCTAssertEqual(result.activityBreakdown[RideActivityKind.cycling.rawValue] ?? 0, 0.6, accuracy: 0.05)
    }
}
