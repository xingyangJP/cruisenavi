import Foundation
import CoreLocation

struct RideIntegrityConfig {
    var sustainedWindow: TimeInterval = 3.0   // seconds
    var maxPlausibleKmh: Double = 90.0        // sanity cap
    var minValidSampleRatio: Double = 0.6     // eligibility threshold
    /// §4.2 vehicle-suspicion: samples are excluded as vehicle travel only when speed stays above
    /// this for `sustainedVehicleSeconds` CONTINUOUSLY without positive `.cycling` confirmation.
    /// A single sample above this speed is NOT vehicle evidence — bikes burst past 70 km/h on
    /// descents — and neither is a CoreMotion `.automotive` label on its own: handlebar-mounted
    /// phones read as automotive for most of a genuine ride (no pedaling body motion reaches the
    /// accelerometer), so the label is only trusted when this sustained-cruise rule corroborates it.
    var vehicleCruiseKmh: Double = 50.0
    /// Minimum continuous time above `vehicleCruiseKmh` before a run counts as vehicle cruising.
    /// Cars hold 50+ km/h for minutes; a bike needs a long steep descent to do so, and a descent
    /// that CoreMotion confirms as `.cycling` is still kept.
    var sustainedVehicleSeconds: TimeInterval = 90.0
    static let `default` = RideIntegrityConfig()
}

struct RideIntegrityResult: Equatable {
    let maxSustainedSpeed: Double      // km/h, valid samples only
    let effectiveDistance: Double      // km, valid segments only
    let validSampleRatio: Double       // 0.0–1.0
    let isRankingEligible: Bool
    let activityBreakdown: [String: Double]  // RideActivityKind.rawValue -> time fraction 0–1
}

/// Pure, synchronous anti-cheat analyzer. No CoreMotion/CoreLocation-manager dependency:
/// it consumes already-captured `RideLocationSample`s and `RideActivitySegment`s so it can be
/// unit-tested without a device (mirrors `SpeedNormalizer`).
enum RideIntegrityAnalyzer {
    static func analyze(
        samples: [RideLocationSample],
        segments: [RideActivitySegment],
        config: RideIntegrityConfig = .default
    ) -> RideIntegrityResult {
        // 1. Empty guard.
        guard !samples.isEmpty else {
            return RideIntegrityResult(
                maxSustainedSpeed: 0,
                effectiveDistance: 0,
                validSampleRatio: 0,
                isRankingEligible: false,
                activityBreakdown: [:]
            )
        }

        let orderedSamples = samples.sorted { $0.timestamp < $1.timestamp }

        // 2. Per-sample activity lookup + 3. per-sample validity.
        //
        // Vehicle detection is deliberately conservative about what counts as evidence:
        // - A CoreMotion `.automotive` label alone does NOT invalidate. Handlebar-mounted phones
        //   (the normal setup for a bike-nav app) miss the pedaling body motion that cycling
        //   detection relies on and get classified automotive for most of a legitimate ride.
        // - An instantaneous speed above `vehicleCruiseKmh` alone does NOT invalidate either;
        //   bikes exceed 70 km/h on descents.
        // What DOES read as vehicle travel is *sustained* cruising: staying above
        // `vehicleCruiseKmh` continuously for `sustainedVehicleSeconds` without positive
        // `.cycling` confirmation. This also closes the bypass where a fast car ride yields
        // `.unknown` (or no) segments instead of `.automotive`. The residual gap — a car ride at
        // bike-plausible speeds — is deferred to Phase-B server-side verification (plan §4.4).
        let kinds = orderedSamples.map { coveringKind(for: $0, in: segments) }
        let vehicleSuspect = sustainedVehicleRunFlags(
            orderedSamples: orderedSamples,
            kinds: kinds,
            config: config
        )
        var validity: [Bool] = []
        validity.reserveCapacity(orderedSamples.count)
        for (index, sample) in orderedSamples.enumerated() {
            let isInvalid = sample.speedKmh > config.maxPlausibleKmh
                || sample.horizontalAccuracy < 0
                || vehicleSuspect[index]
            validity.append(!isInvalid)
        }

        // 4. validSampleRatio.
        let validCount = validity.filter { $0 }.count
        let validSampleRatio = Double(validCount) / Double(max(orderedSamples.count, 1))

        // 5. effectiveDistance (km): consecutive valid pairs only.
        var meters: Double = 0
        for index in 1..<max(orderedSamples.count, 1) where index < orderedSamples.count {
            guard validity[index - 1] && validity[index] else { continue }
            let a = orderedSamples[index - 1]
            let b = orderedSamples[index]
            let locA = CLLocation(latitude: a.latitude, longitude: a.longitude)
            let locB = CLLocation(latitude: b.latitude, longitude: b.longitude)
            meters += locA.distance(from: locB)
        }
        let effectiveDistance = meters / 1000.0

        // 6. maxSustainedSpeed (km/h): 3s sustained peak over valid samples only.
        let validSamples = zip(orderedSamples, validity).compactMap { $0.1 ? $0.0 : nil }
        let maxSustainedSpeed = maxSustainedSpeed(in: validSamples, window: config.sustainedWindow)

        // 7. activityBreakdown.
        let activityBreakdown = activityBreakdown(orderedSamples: orderedSamples, segments: segments)

        // 8. isRankingEligible.
        // Note the residual Phase-A limitation (plan §4.1 / §10): on devices where CoreMotion is
        // unavailable or denied, `segments` is empty and eligibility falls back to the speed-sanity
        // filters above (max-plausible cap + §4.2 vehicle-cruise). A LOW-speed vehicle ride
        // (< vehicleCruiseKmh) on such a device cannot be distinguished from cycling here; that
        // gap is intentionally deferred to Phase-B server-side verification (§4.4).
        // The old `maxSustainedSpeed <= maxPlausibleKmh` guard was removed: maxSustainedSpeed is a
        // window-minimum over already-cap-filtered valid samples, so it is <= the cap by
        // construction and the clause was dead code.
        let isRankingEligible = validSampleRatio >= config.minValidSampleRatio
            && !orderedSamples.isEmpty

        return RideIntegrityResult(
            maxSustainedSpeed: maxSustainedSpeed,
            effectiveDistance: effectiveDistance,
            validSampleRatio: validSampleRatio,
            isRankingEligible: isRankingEligible,
            activityBreakdown: activityBreakdown
        )
    }

    /// Flags samples that sit inside a sustained vehicle-cruise run: a maximal stretch of
    /// consecutive samples all above `vehicleCruiseKmh` and none positively confirmed `.cycling`,
    /// spanning at least `sustainedVehicleSeconds`. Runs shorter than that are treated as
    /// legitimate bursts (descents) and kept.
    private static func sustainedVehicleRunFlags(
        orderedSamples: [RideLocationSample],
        kinds: [RideActivityKind],
        config: RideIntegrityConfig
    ) -> [Bool] {
        var flags = [Bool](repeating: false, count: orderedSamples.count)
        var runStart: Int? = nil
        for index in 0...orderedSamples.count {
            let inRun = index < orderedSamples.count
                && orderedSamples[index].speedKmh > config.vehicleCruiseKmh
                && kinds[index] != .cycling
            if inRun {
                if runStart == nil { runStart = index }
            } else if let start = runStart {
                let span = orderedSamples[index - 1].timestamp
                    .timeIntervalSince(orderedSamples[start].timestamp)
                if span >= config.sustainedVehicleSeconds {
                    for i in start..<index { flags[i] = true }
                }
                runStart = nil
            }
        }
        return flags
    }

    /// Finds the covering segment for a sample. If multiple match, prefers highest confidence
    /// (tie => first). If none match, returns `.unknown`.
    private static func coveringKind(
        for sample: RideLocationSample,
        in segments: [RideActivitySegment]
    ) -> RideActivityKind {
        var best: RideActivitySegment?
        for segment in segments where segment.startTime <= sample.timestamp && sample.timestamp < segment.endTime {
            if let current = best {
                if segment.confidence > current.confidence {
                    best = segment
                }
            } else {
                best = segment
            }
        }
        return best?.kind ?? .unknown
    }

    /// The peak of the per-window minimum speed across all windows that span >= `window` seconds.
    /// Using the window minimum guarantees a single 1-sample GPS spike cannot set the record —
    /// a value only counts if it was held for the full window. If no window spans >= `window`
    /// (ride too short / too few valid samples), falls back to 0 (not an instantaneous spike).
    private static func maxSustainedSpeed(
        in validSamples: [RideLocationSample],
        window: TimeInterval
    ) -> Double {
        guard validSamples.count > 1 else { return 0 }
        var best = 0.0
        var qualifiedAny = false
        for i in 0..<validSamples.count {
            // Accumulate the running minimum speed from start sample `i` until the span first
            // reaches the full window, then record. Bounding by `<= window` (the previous bug)
            // only ever recorded when a sample landed EXACTLY at `window` seconds, which real
            // sub-second GPS timestamps never hit — so this must extend PAST `window` to qualify.
            var windowMin = validSamples[i].speedKmh
            var qualified = false
            var j = i
            while j < validSamples.count {
                windowMin = min(windowMin, validSamples[j].speedKmh)
                if validSamples[j].timestamp.timeIntervalSince(validSamples[i].timestamp) >= window {
                    qualified = true
                    break   // a longer window can only lower the minimum
                }
                j += 1
            }
            if qualified {
                qualifiedAny = true
                best = max(best, windowMin)
            }
        }
        return qualifiedAny ? best : 0
    }

    /// Per-kind fraction of total ride time, clipping each segment to the sample time span.
    /// Omits zero-duration kinds. Returns [:] if total ride time is not positive.
    private static func activityBreakdown(
        orderedSamples: [RideLocationSample],
        segments: [RideActivitySegment]
    ) -> [String: Double] {
        guard let first = orderedSamples.first, let last = orderedSamples.last else { return [:] }
        let spanStart = first.timestamp
        let spanEnd = last.timestamp
        let total = spanEnd.timeIntervalSince(spanStart)
        guard total > 0 else { return [:] }

        var durations: [String: Double] = [:]
        for segment in segments {
            let clippedStart = max(segment.startTime, spanStart)
            let clippedEnd = min(segment.endTime, spanEnd)
            let duration = clippedEnd.timeIntervalSince(clippedStart)
            guard duration > 0 else { continue }
            durations[segment.kind.rawValue, default: 0] += duration
        }

        var breakdown: [String: Double] = [:]
        for (kind, duration) in durations where duration > 0 {
            breakdown[kind] = duration / total
        }
        return breakdown
    }
}
