/**
 * RideLane — World Ranking server-side anti-cheat Cloud Functions.
 *
 * Design source of truth:
 *   - docs/RANKING_MODE_PLAN.md  §4.4 (server validation), §5.3 (data model), §5.4 (identity)
 *   - docs/RANKING_GOLIVE_CHECKLIST.md §6 (Cloud Functions runbook)
 *   - firestore.rules            (the DEPLOYED rules this Function complements)
 *
 * WHY THIS EXISTS
 * ---------------
 * The deployed security rules make the public leaderboard `list` return ONLY documents
 * where `verified == true`, and clients can NEVER write `verified` / `region` / `country`.
 * So a client-created entry is INVISIBLE on the public board until a trusted server stamps
 * `verified = true`. This Function is that trusted server: it runs with the Admin SDK
 * (which bypasses security rules) and is the authoritative anti-cheat gate. Nothing shows
 * on the public board unless this Function approves it.
 *
 * FAIL-CLOSED POSTURE
 * -------------------
 * On ANY uncertainty (missing integrity record, malformed data, metric mismatch, rate-limit
 * exhaustion, thrown error) we DO NOT verify. We stamp `verified = false`, leaving the entry
 * invisible. We only ever set `verified = true` when every check below passes.
 *
 * TRACE-RECOMPUTE LIMITATION (important, documented in README.md)
 * --------------------------------------------------------------
 * GPS traces are never uploaded (privacy, plan §8.1). This Function therefore validates the
 * client-submitted leaderboard `value` against the ON-DEVICE integrity summary written to the
 * private `rankingSubmissions/{uid}/rides/{rideId}` doc — it is NOT an independent server-side
 * recomputation from raw GPS. It is defense against a client that lies in the *public* entry
 * while its own *private* integrity record disagrees, plus plausibility caps, rate limiting,
 * and banning. A client that fabricates BOTH the entry and a matching integrity record is not
 * caught here; that requires a future raw-trace pipeline (plan §4.4 "recompute").
 */

import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions/v2";
import { initializeApp } from "firebase-admin/app";
import {
  getFirestore,
  FieldValue,
  Timestamp,
  Transaction,
  DocumentReference,
} from "firebase-admin/firestore";

initializeApp();
const db = getFirestore();

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/**
 * Region MUST match the Firestore database region (asia-northeast1 / Tokyo, per go-live
 * checklist §1.1). A trigger in a different region than the DB is rejected / mis-routed.
 */
const REGION = "asia-northeast1";

/**
 * Allowed leaderboard metric path segments. These MUST match `isAllowedMetric()` in the
 * DEPLOYED firestore.rules (`['longestDistance', 'topSpeed']`) and the ids the client's
 * FirestoreWorldRankingService derives from RankingMetric. (NOTE: the checklist §3.0 code
 * template maps `.longestDistance -> "distance"`, which is STALE and contradicts the
 * deployed rules; the deployed rules win. See README.md "Metric ids".)
 */
const METRIC_LONGEST_DISTANCE = "longestDistance";
const METRIC_TOP_SPEED = "topSpeed";
const ALLOWED_METRICS = new Set<string>([METRIC_LONGEST_DISTANCE, METRIC_TOP_SPEED]);

/**
 * Per-metric plausibility caps — defense-in-depth (plan §4.2, and the same numbers baked
 * into firestore.rules `maxValueFor`). topSpeed ≤ 90 km/h, longestDistance ≤ 2000 km.
 * A value above the cap is not just rejected, it is treated as egregious (auto-ban).
 */
const CAPS: Record<string, number> = {
  [METRIC_TOP_SPEED]: 90, // km/h
  [METRIC_LONGEST_DISTANCE]: 2000, // km
};

/**
 * Eligibility threshold — MUST match RideIntegrityConfig.minValidSampleRatio (0.6) in
 * Sources/Services/Integrity/RideIntegrityAnalyzer.swift.
 */
const MIN_VALID_SAMPLE_RATIO = 0.6;

/**
 * Anti-inflation tolerance for entry.value vs the integrity value. A tiny relative + absolute
 * slack absorbs float rounding and unit drift. UNDER-reporting (value below integrity) is
 * always allowed — only OVER-reporting is a cheat.
 */
const VALUE_REL_TOLERANCE = 0.05; // 5%
const VALUE_ABS_TOLERANCE: Record<string, number> = {
  [METRIC_TOP_SPEED]: 1.0, // km/h
  [METRIC_LONGEST_DISTANCE]: 0.1, // km
};

/**
 * Inflation past this multiple of the real (integrity) value is "egregious" → immediate ban.
 * e.g. claiming 40 km/h on a ride the device measured at 20 km/h.
 */
const EGREGIOUS_INFLATION_FACTOR = 1.5;

/** achievedAt sane window (defense-in-depth; rules already bound this too). */
const ACHIEVED_AT_FLOOR = Timestamp.fromDate(new Date("2020-01-01T00:00:00Z"));
const ACHIEVED_AT_FUTURE_SKEW_MS = 5 * 60 * 1000; // allow 5 min of clock skew

/** Rate limiting: cap successful verifications per uid per rolling 24h window (plan §4.4). */
const RATE_WINDOW_MS = 24 * 60 * 60 * 1000;
const MAX_VERIFICATIONS_PER_WINDOW = 30;

/** Repeated rejects inside the rolling window → ban (spam/abuse). */
const REJECT_BAN_THRESHOLD = 5;

/** Server-only collections (default-deny in firestore.rules — clients cannot read/write). */
const MODERATION_COLLECTION = "rankingModeration"; // presence == banned (rules isBanned())
const RATE_LIMIT_COLLECTION = "rankingRateLimits"; // rolling verification/reject counters
const SUBMISSIONS_COLLECTION = "rankingSubmissions"; // private on-device integrity records

// ---------------------------------------------------------------------------
// Types (loose — Firestore data is untyped; we validate defensively)
// ---------------------------------------------------------------------------

type EntryData = {
  userId?: unknown;
  displayName?: unknown;
  value?: unknown;
  achievedAt?: unknown;
  rideId?: unknown;
  verified?: unknown;
  region?: unknown;
  country?: unknown;
  validatedAt?: unknown;
};

type IntegrityData = {
  metric?: unknown;
  value?: unknown;
  effectiveDistance?: unknown;
  maxSustainedSpeed?: unknown;
  validSampleRatio?: unknown;
  isRankingEligible?: unknown;
  activityBreakdown?: unknown;
  achievedAt?: unknown;
};

/** Outcome of a validation pass. */
type Verdict =
  | { kind: "verify" }
  | { kind: "reject"; reason: string }
  | { kind: "ban"; reason: string };

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

function isFiniteNumber(x: unknown): x is number {
  return typeof x === "number" && Number.isFinite(x);
}

/** Keys that this Function itself writes to the ENTRY doc. */
const SERVER_ONLY_ENTRY_KEYS = new Set<string>([
  "verified",
  "region",
  "country",
  "validatedAt",
]);

/**
 * IDEMPOTENCY / anti-loop guard.
 *
 * This Function writes `verified`/`validatedAt` (etc.) back onto the SAME entry doc it is
 * triggered on, which re-fires the trigger. We must short-circuit our own writes or we loop
 * forever (and burn quota).
 *
 * Rule: if EVERY field that changed between `before` and `after` is one of the server-only
 * keys this Function writes, the change was caused by us — skip. Any client-driven change
 * (value, displayName, achievedAt, rideId, userId) touches a NON-server key and is validated.
 *
 * `before` is undefined on the initial client create; that is a genuine client change → validate.
 */
function isOwnServerWrite(
  before: EntryData | undefined,
  after: EntryData
): boolean {
  if (!before) return false; // create → validate

  const keys = new Set<string>([...Object.keys(before), ...Object.keys(after)]);
  for (const key of keys) {
    if (SERVER_ONLY_ENTRY_KEYS.has(key)) continue; // ignore fields we own
    if (!deepEqual((before as Record<string, unknown>)[key], (after as Record<string, unknown>)[key])) {
      return false; // a client-writable field changed → this is a real submission
    }
  }
  return true; // only server-only fields changed → our own write → skip
}

/** Firestore-value equality good enough for our scalar client fields + Timestamp. */
function deepEqual(a: unknown, b: unknown): boolean {
  if (a === b) return true;
  if (a instanceof Timestamp && b instanceof Timestamp) return a.isEqual(b);
  // Fall back to JSON for the rare nested value; client entry fields are all scalars.
  try {
    return JSON.stringify(a) === JSON.stringify(b);
  } catch {
    return false;
  }
}

/** The integrity field to compare against for a given metric. */
function integrityValueFor(metric: string, rec: IntegrityData): number | null {
  const raw =
    metric === METRIC_LONGEST_DISTANCE
      ? rec.effectiveDistance
      : rec.maxSustainedSpeed;
  return isFiniteNumber(raw) ? raw : null;
}

/**
 * Anti-inflation allowance: the maximum entry.value we accept for a given real integrity value,
 * clamped by the plausibility cap. entry.value above this is over-reported.
 */
function maxAcceptedValue(metric: string, integrityValue: number): number {
  const rel = integrityValue * (1 + VALUE_REL_TOLERANCE);
  const abs = integrityValue + (VALUE_ABS_TOLERANCE[metric] ?? 0);
  return Math.min(Math.max(rel, abs), CAPS[metric]);
}

// ---------------------------------------------------------------------------
// The §4.4 validation trigger
// ---------------------------------------------------------------------------

export const validateLeaderboardEntry = onDocumentWritten(
  {
    document: "leaderboards/{metric}/entries/{uid}",
    region: REGION,
    // Keep it single-instance-friendly; validation is light and idempotent.
    retry: false,
  },
  async (event) => {
    const metric = event.params.metric as string;
    const uid = event.params.uid as string;

    const beforeSnap = event.data?.before;
    const afterSnap = event.data?.after;

    // ---- Change-shape handling -------------------------------------------
    // DELETE (after gone): nothing to verify. Durable ban/rate state lives in separate
    // server-only collections, so delete+recreate cannot launder standing (rules re-check
    // isBanned() on create). Just return.
    if (!afterSnap?.exists) {
      return;
    }

    const after = afterSnap.data() as EntryData;
    const before = beforeSnap?.exists ? (beforeSnap.data() as EntryData) : undefined;

    // ---- Idempotency: skip our own server-only writes (no infinite retrigger) ----
    if (isOwnServerWrite(before, after)) {
      return;
    }

    const entryRef = afterSnap.ref;

    try {
      const verdict = await evaluate(metric, uid, after);

      switch (verdict.kind) {
        case "verify":
          await stampVerified(entryRef, true);
          logger.info("verified", { uid, metric, value: after.value });
          break;

        case "reject":
          await stampVerified(entryRef, false);
          // A reject counts toward the abuse budget; enough rejects → ban.
          await recordRejectAndMaybeBan(uid, metric, verdict.reason, after);
          logger.warn("rejected", { uid, metric, reason: verdict.reason });
          break;

        case "ban":
          await stampVerified(entryRef, false);
          await ban(uid, metric, verdict.reason, after);
          logger.error("banned", { uid, metric, reason: verdict.reason });
          break;
      }
    } catch (err) {
      // FAIL CLOSED: on any unexpected error, ensure the entry is NOT verified.
      logger.error("validation error — failing closed", { uid, metric, err: String(err) });
      try {
        await stampVerified(entryRef, false);
      } catch (inner) {
        logger.error("failed to stamp verified=false", { uid, metric, err: String(inner) });
      }
    }
  }
);

// ---------------------------------------------------------------------------
// Validation core (ordered, fail-closed)
// ---------------------------------------------------------------------------

async function evaluate(
  metric: string,
  uid: string,
  entry: EntryData
): Promise<Verdict> {
  // 0. Metric must be a known board. (The path could technically carry anything.)
  if (!ALLOWED_METRICS.has(metric)) {
    return { kind: "reject", reason: `unknown-metric:${metric}` };
  }

  // 1. Entry shape / ownership sanity (defense-in-depth; rules already enforce most).
  if (entry.userId !== uid) {
    return { kind: "reject", reason: "userId-mismatch" };
  }
  if (!isFiniteNumber(entry.value) || entry.value < 0) {
    return { kind: "reject", reason: "value-not-a-number" };
  }
  const value = entry.value;

  // 2. Plausibility cap (defense-in-depth). Above the cap is absurd → egregious → ban.
  const cap = CAPS[metric];
  if (value > cap) {
    return { kind: "ban", reason: `value-above-cap:${value}>${cap}` };
  }

  // 3. achievedAt within a sane window.
  const achievedAt = entry.achievedAt;
  if (!(achievedAt instanceof Timestamp)) {
    return { kind: "reject", reason: "achievedAt-not-timestamp" };
  }
  if (achievedAt.toMillis() < ACHIEVED_AT_FLOOR.toMillis()) {
    return { kind: "reject", reason: "achievedAt-too-old" };
  }
  if (achievedAt.toMillis() > Date.now() + ACHIEVED_AT_FUTURE_SKEW_MS) {
    return { kind: "reject", reason: "achievedAt-in-future" };
  }

  // 4. rideId must be a usable, single-segment doc id (no path traversal).
  const rideId = entry.rideId;
  if (typeof rideId !== "string" || rideId.length === 0 || rideId.length > 128 || rideId.includes("/")) {
    return { kind: "reject", reason: "rideId-invalid" };
  }

  // 5. The private on-device integrity record MUST exist under THIS uid.
  //    Path ownership (rankingSubmissions/{uid}/rides/{rideId}) guarantees the uid.
  const recSnap = await db
    .collection(SUBMISSIONS_COLLECTION)
    .doc(uid)
    .collection("rides")
    .doc(rideId)
    .get();

  if (!recSnap.exists) {
    return { kind: "reject", reason: "integrity-record-missing" };
  }
  const rec = recSnap.data() as IntegrityData;

  // 6. Integrity record's metric must match the board being submitted to.
  if (rec.metric !== metric) {
    return { kind: "reject", reason: `integrity-metric-mismatch:${String(rec.metric)}!=${metric}` };
  }

  // 7. On-device eligibility gate — mirrors RideIntegrityAnalyzer.
  if (rec.isRankingEligible !== true) {
    return { kind: "reject", reason: "not-ranking-eligible" };
  }
  if (!isFiniteNumber(rec.validSampleRatio) || rec.validSampleRatio < MIN_VALID_SAMPLE_RATIO) {
    return { kind: "reject", reason: `low-valid-sample-ratio:${String(rec.validSampleRatio)}` };
  }

  // 8. entry.value must match the correct integrity field (anti-inflation).
  const integrityValue = integrityValueFor(metric, rec);
  if (integrityValue === null || integrityValue < 0) {
    return { kind: "reject", reason: "integrity-value-missing" };
  }
  // A tampered device could also push the integrity value itself over the cap.
  if (integrityValue > cap) {
    return { kind: "ban", reason: `integrity-value-above-cap:${integrityValue}>${cap}` };
  }
  // Egregious inflation of the public value over the private record → immediate ban.
  if (integrityValue > 0 && value > integrityValue * EGREGIOUS_INFLATION_FACTOR) {
    return {
      kind: "ban",
      reason: `egregious-inflation:${value}>${integrityValue}x${EGREGIOUS_INFLATION_FACTOR}`,
    };
  }
  // Ordinary over-reporting beyond tolerance → reject (invisible, no ban yet).
  if (value > maxAcceptedValue(metric, integrityValue)) {
    return { kind: "reject", reason: `value-exceeds-integrity:${value}>~${integrityValue}` };
  }

  // 9. Rate limit — cap successful verifications per uid per rolling window. This both
  //    reserves a slot (transactionally) AND decides pass/fail, so it must be LAST so we
  //    never consume a verification slot for an entry that would have failed anyway.
  const allowed = await reserveVerificationSlot(uid);
  if (!allowed) {
    return { kind: "reject", reason: "rate-limited" };
  }

  return { kind: "verify" };
}

// ---------------------------------------------------------------------------
// Server-only writes (Admin SDK — bypasses firestore.rules)
// ---------------------------------------------------------------------------

/**
 * Set the server-only `verified` flag on the entry. `merge:true` so we never clobber the
 * client-writable fields. We intentionally do NOT set region/country here: without an uploaded
 * GPS trace there is no trustworthy server signal to derive them from (see README limitation).
 */
async function stampVerified(entryRef: DocumentReference, verified: boolean): Promise<void> {
  await entryRef.set(
    {
      verified,
      validatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
}

/**
 * Transactionally prune the rolling window and reserve a verification slot for `uid`.
 * Returns false when the uid already has MAX_VERIFICATIONS_PER_WINDOW successful
 * verifications inside RATE_WINDOW_MS. Writes to a SEPARATE collection so it does NOT
 * re-trigger this Function. NOTE: this is NOT the ban collection, so counting here never
 * accidentally bans a legitimate user.
 */
async function reserveVerificationSlot(uid: string): Promise<boolean> {
  const ref = db.collection(RATE_LIMIT_COLLECTION).doc(uid);
  return db.runTransaction(async (tx: Transaction) => {
    const snap = await tx.get(ref);
    const now = Date.now();
    const cutoff = now - RATE_WINDOW_MS;

    const prev = (snap.exists ? snap.data() : {}) as { verifiedAt?: number[] };
    const recent = Array.isArray(prev.verifiedAt)
      ? prev.verifiedAt.filter((t) => typeof t === "number" && t >= cutoff)
      : [];

    if (recent.length >= MAX_VERIFICATIONS_PER_WINDOW) {
      // Persist the pruned list even on rejection so the window keeps sliding.
      tx.set(ref, { verifiedAt: recent, updatedAt: now }, { merge: true });
      return false;
    }

    recent.push(now);
    tx.set(ref, { verifiedAt: recent, updatedAt: now }, { merge: true });
    return true;
  });
}

/**
 * Record a rejection in the rolling window and BAN once rejects cross the threshold — this is
 * the "many rejects" abuse trigger from §4.4. Reject bookkeeping lives in the rate-limit doc
 * (a non-ban, server-only collection); only when it crosses REJECT_BAN_THRESHOLD do we write
 * the actual ban doc.
 */
async function recordRejectAndMaybeBan(
  uid: string,
  metric: string,
  reason: string,
  entry: EntryData
): Promise<void> {
  const ref = db.collection(RATE_LIMIT_COLLECTION).doc(uid);
  const crossed = await db.runTransaction(async (tx: Transaction) => {
    const snap = await tx.get(ref);
    const now = Date.now();
    const cutoff = now - RATE_WINDOW_MS;

    const prev = (snap.exists ? snap.data() : {}) as { rejectAt?: number[] };
    const recent = Array.isArray(prev.rejectAt)
      ? prev.rejectAt.filter((t) => typeof t === "number" && t >= cutoff)
      : [];
    recent.push(now);

    tx.set(ref, { rejectAt: recent, updatedAt: now }, { merge: true });
    return recent.length >= REJECT_BAN_THRESHOLD;
  });

  if (crossed) {
    await ban(uid, metric, `repeated-rejects>=${REJECT_BAN_THRESHOLD}:${reason}`, entry);
  }
}

/**
 * Write the ban doc to rankingModeration/{uid}. Its mere EXISTENCE is what the deployed
 * firestore.rules `isBanned()` checks to hard-block further create/update — so this also
 * defeats the delete-and-recreate "launder my standing" bypass. Written only by this trusted
 * server (Admin SDK); the collection is default-deny to clients.
 */
async function ban(
  uid: string,
  metric: string,
  reason: string,
  entry: EntryData
): Promise<void> {
  await db.collection(MODERATION_COLLECTION).doc(uid).set(
    {
      uid,
      reason,
      metric,
      offendingValue: isFiniteNumber(entry.value) ? entry.value : null,
      source: "validateLeaderboardEntry",
      bannedAt: FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
}

// ---------------------------------------------------------------------------
// OPTIONAL / STRETCH (outline only — not wired): manual moderation.
// ---------------------------------------------------------------------------
//
// A callable to let a trusted operator lift a ban or force-quarantine an entry could be added
// here, e.g.:
//
//   export const moderateEntry = onCall({ region: REGION }, async (req) => {
//     // 1. AuthZ: require a custom claim, e.g. req.auth?.token.rankingAdmin === true.
//     // 2. action "unban" -> delete rankingModeration/{uid}; "ban" -> ban(...);
//     //    "unverify" -> stampVerified(entryRef, false).
//     // 3. Audit-log the operator uid + action.
//   });
//
// Left as an outline per task scope; the automated trigger above is the deliverable.
