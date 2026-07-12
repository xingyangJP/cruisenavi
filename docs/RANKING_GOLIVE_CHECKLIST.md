# RideLane World Ranking — Phase B Go-Live Checklist

> Scope: turn the **mock** world ranking (Phase B scaffolding) into a live
> Firebase/Firestore-backed leaderboard with the least possible regression risk.
> Companion design doc: [RANKING_MODE_PLAN.md](RANKING_MODE_PLAN.md) — read §4.4,
> §5.3, §5.4, §5.5, §8 first. This file is the *ordered runbook*; the plan is the *why*.
>
> Firebase project id: **`ridelane`** (already created). `GoogleService-Info.plist`
> (repo root + app bundle) already targets it — `PROJECT_ID=ridelane`,
> `BUNDLE_ID=com.xerographix.SeaNavi`.
>
> **Current state (verified in repo):**
> - `WorldRankingService` protocol + `MockWorldRankingService` exist and are wired.
> - `NavigationDashboardViewModel` injects the mock by **default parameter**
>   (`worldRankingService: WorldRankingService = MockWorldRankingService()`),
>   and `SeaNaviApp.swift` constructs the view model *without* overriding it.
> - `RankingIdentityProviding` returns an anonymous persisted UUID today
>   (`AnonymousRankingIdentityProvider`); Sign in with Apple plugs into this seam.
> - `firestore.rules` is **deny-all** (safe default). `firebase.json`/`.firebaserc`
>   are wired to project `ridelane`. `scripts/fb-deploy.sh` is the only sanctioned deploy path.
> - Firebase products linked today: **`FirebaseAnalytics` only** (via `FirebaseCore`).
>   `FirebaseFirestore` and `FirebaseAuth` are **not** yet added.

---

## 0. Preconditions / order-of-operations

Do the steps **in this order**. Each stage is independently verifiable and each is a
natural rollback point. Nothing below flips the live app until Step 8.

```
1. Portal setup (Console + Apple Developer)   ← irreversible location choice here
2. Xcode: add SPM products + capability        ← app compiles against Firestore/Auth
3. Paste-in Swift templates (new files only)   ← code exists but not yet injected
4. Author firestore.rules + indexes locally
5. Deploy rules + indexes via guarded wrapper
6. Cloud Functions server-side validation
7. Verification on emulator / staging
8. Flip the backend (Mock → Firestore) in SeaNaviApp.swift
9. Final end-to-end verification
```

---

## 1. External / portal steps (cannot be scripted)

These happen in web consoles and are **not** covered by `scripts/fb-deploy.sh`.

### 1.1 Firebase Console — create the Cloud Firestore database

1. Console → project **`ridelane`** → Build → **Firestore Database** → *Create database*.
2. **CHOOSE A LOCATION — THIS IS IRREVERSIBLE.** ⚠️ The Firestore location cannot be
   changed after creation; the only "fix" is to delete the database and recreate it
   (losing all data). For a **JP-first** app, pick an **`asia-northeast`** region:
   - `asia-northeast1` (Tokyo) — recommended default.
   - `asia-northeast2` (Osaka) — alternative in-region.
   - Prefer a single-region location (lower cost, lowest JP latency) over `nam5`/`eur3`
     multi-region unless you have a specific global-durability requirement.
3. Start in **Production mode** (locked rules). We ship real rules in Step 5; do **not**
   leave it in test mode.
4. Do **not** create the database from the CLI/MCP in this repo — it is a live-mutating
   action outside the guarded wrapper. Create it by hand in the Console so the location
   choice is deliberate.

### 1.2 Firebase Console — enable Authentication providers

1. Console → Build → **Authentication** → *Get started*.
2. Enable **Apple** provider (iOS) — you'll wire the Services ID / key from §1.4.
3. Enable **Google** provider (needed for the future Android client per §5.3; enabling
   now keeps the shared `uid` model consistent). Set the project support email.
4. Add the **authorized domain**/redirect config the Apple provider asks for.

### 1.3 Apple Developer — Sign in with Apple capability + Service configuration

1. Apple Developer → Certificates, Identifiers & Profiles → **Identifiers** → App ID
   `com.xerographix.SeaNavi` → enable the **Sign in with Apple** capability.
2. Create a **Services ID** and a **Sign in with Apple key (.p8)** if Firebase's Apple
   provider requests them (required for the OAuth/web leg Firebase uses). Record:
   - Services ID
   - Key ID + Team ID
   - the `.p8` private key (store securely — never commit it)
3. Paste these into the Firebase Console **Apple provider** config (from §1.2).
4. Apple review requirement (§5.4, App Store 5.1.1(v)): because we adopt Sign in with
   Apple, the app must offer an **in-app account-deletion** path. Track this as a
   blocking release item (it deletes the Firestore entry + signs out; see §9 checklist).

### 1.4 Billing — Blaze plan

- **Cloud Functions require the Blaze (pay-as-you-go) plan.** Upgrade project `ridelane`
  to Blaze *before* Step 6. Firestore reads/writes are billable too; keep the Top-100 +
  cache strategy from §5.3/§10 to bound read cost. Set a **budget alert** in GCP billing.

---

## 2. Xcode steps

> The `firebase-ios-sdk` Swift Package is **already resolved** for `FirebaseAnalytics`.
> This step **adds two products from the same package** — it does not add a new package.

### 2.1 Add SPM products to the **SeaNavi** target

1. Open `SeaNavi/RideLane.xcodeproj`.
2. Target **SeaNavi** → *General* → *Frameworks, Libraries, and Embedded Content*
   (or *Package Dependencies* → the existing `firebase-ios-sdk` entry → *Add products*).
3. Add:
   - **FirebaseFirestore**
   - **FirebaseAuth**
4. Keep the existing `FirebaseCore` / `FirebaseAnalytics` products.

> ⚠️ **Build-time note:** `FirebaseFirestore` pulls in heavy C++ dependencies
> (`abseil`, `gRPC`, `leveldb`, `BoringSSL`). First clean build gets noticeably slower
> and the binary grows. This is expected — budget CI time accordingly. No source change
> is needed for the app to keep compiling; the new products are only *referenced* once
> the Step 3 files are added.

### 2.2 Add the Sign in with Apple capability/entitlement

1. Target **SeaNavi** → *Signing & Capabilities* → **+ Capability** → **Sign in with Apple**.
2. This adds the `com.apple.developer.applesignin` entitlement (`Default`). Ensure the
   provisioning profile refreshes to include the capability from §1.3.

> This is the only project-level change required for auth. Do it as its own commit so it
> can be reverted independently if signing breaks.

---

## 3. Paste-ready Swift code templates

> ⚠️ **All code in this section is a TEMPLATE. Add these as NEW files AFTER the SPM
> products from Step 2 exist** — they `import FirebaseFirestore` / `import FirebaseAuth`
> and will not compile before then. They conform to the **existing** protocols
> (`WorldRankingService`, `RankingIdentityProviding`) so nothing else changes. Do not
> paste them over existing files.

### 3.0 Metric → Firestore path segment (shared helper)

`RankingMetric` (in `Sources/Models/PersonalRanking.swift`) has **no `rawValue`**:

```swift
enum RankingMetric: CaseIterable { case longestDistance; case topSpeed }
```

The Firestore path is `leaderboards/{metric}/entries/{userId}` (§5.3), so we need a
stable string id per metric. Add this small extension in the new service file:

```swift
// TEMPLATE — new code. Maps the app metric to a STABLE Firestore path segment.
// These strings become collection ids in Firestore — never change them after go-live.
extension RankingMetric {
    var firestoreMetricId: String {
        switch self {
        case .longestDistance: return "distance"   // best distance km board
        case .topSpeed:        return "topSpeed"    // best speed km/h board
        }
    }
}
```

### 3.1 `FirestoreWorldRankingService` (conforms to `WorldRankingService`)

Matches the exact protocol signature verified in
`Sources/Services/Ranking/WorldRankingService.swift`. It upserts to
`leaderboards/{metricId}/entries/{uid}` and reads Top-N ordered by `value` desc, then
merges the current user's own row/rank (fetched by doc id) so the UI can pin it — same
shape `MockWorldRankingService` returns (`WorldRankingBoard(metric:entries:isMockData:)`,
rows are `WorldRankingEntry(id:rank:nickname:value:region:isCurrentUser:)`).

```swift
// TEMPLATE — new file, e.g. Sources/Services/Ranking/FirestoreWorldRankingService.swift
// Requires SPM products FirebaseFirestore + FirebaseAuth (Step 2).
import Foundation
import FirebaseFirestore

/// Live Firestore-backed world ranking. Conforms to the SAME `WorldRankingService`
/// protocol the mock uses, so it drops into NavigationDashboardViewModel unchanged.
/// Path: leaderboards/{metricId}/entries/{uid}   (RANKING_MODE_PLAN.md §5.3)
struct FirestoreWorldRankingService: WorldRankingService {
    private let db: Firestore
    private let topN: Int

    init(db: Firestore = Firestore.firestore(), topN: Int = 100) {
        self.db = db
        self.topN = topN
    }

    private func entries(for metric: RankingMetric) -> CollectionReference {
        db.collection("leaderboards")
            .document(metric.firestoreMetricId)
            .collection("entries")
    }

    // MARK: Read

    func fetchLeaderboard(
        metric: RankingMetric,
        userBest: Double,
        accountId: String,
        nickname: String
    ) async -> WorldRankingBoard {
        let col = entries(for: metric)
        do {
            // Top-N ordered by value desc (needs the composite/single-field index, Step 4).
            let snap = try await col
                .order(by: "value", descending: true)
                .limit(to: topN)
                .getDocuments()

            var rows: [WorldRankingEntry] = snap.documents.enumerated().map { index, doc in
                let d = doc.data()
                return WorldRankingEntry(
                    id: doc.documentID,
                    rank: index + 1,
                    nickname: d["displayName"] as? String ?? "",
                    value: d["value"] as? Double ?? 0,
                    region: d["region"] as? String,
                    isCurrentUser: doc.documentID == accountId
                )
            }

            // Ensure the user's own row is present/pinned even if outside Top-N.
            if !rows.contains(where: { $0.isCurrentUser }), !accountId.isEmpty {
                let ownRank = try? await rankOf(value: userBest, in: col)
                rows.append(
                    WorldRankingEntry(
                        id: accountId,
                        rank: ownRank ?? (rows.count + 1),
                        nickname: nickname,
                        value: max(userBest, 0),
                        region: nil,
                        isCurrentUser: true
                    )
                )
            }

            return WorldRankingBoard(metric: metric, entries: rows, isMockData: false)
        } catch {
            // Degrade gracefully: never crash the ranking screen on a network/permission error.
            #if DEBUG
            print("FirestoreWorldRankingService.fetch failed: \(error)")
            #endif
            let ownRow = WorldRankingEntry(
                id: accountId, rank: 1, nickname: nickname,
                value: max(userBest, 0), region: nil, isCurrentUser: true
            )
            return WorldRankingBoard(
                metric: metric,
                entries: accountId.isEmpty ? [] : [ownRow],
                isMockData: false
            )
        }
    }

    /// "1 + number of entries strictly greater than value". One count aggregation query.
    private func rankOf(value: Double, in col: CollectionReference) async throws -> Int {
        let greater = try await col.whereField("value", isGreaterThan: value)
            .count.getAggregation(source: .server)
        return greater.count.intValue + 1
    }

    // MARK: Write — self-best updates only (cost minimization, §5.3)

    func submitBest(
        metric: RankingMetric,
        value: Double,
        accountId: String,
        nickname: String
    ) async {
        guard !accountId.isEmpty, value > 0 else { return }
        let doc = entries(for: metric).document(accountId)   // doc id == uid (owner-only write)
        // NOTE: never write `verified` from the client — Cloud Functions owns it (§4.4 / Step 6).
        let payload: [String: Any] = [
            "userId": accountId,
            "displayName": nickname,
            "value": value,
            "achievedAt": FieldValue.serverTimestamp(),
            "rideId": UUID().uuidString   // replace with the real VoyageLog.id when available
        ]
        do {
            // merge:true so we never clobber the Function-set `verified`/`region` fields.
            try await doc.setData(payload, merge: true)
        } catch {
            #if DEBUG
            print("FirestoreWorldRankingService.submit failed: \(error)")
            #endif
        }
    }
}
```

### 3.2 Firebase Auth + Sign in with Apple identity provider

Conforms to the existing `RankingIdentityProviding` seam
(`Sources/Services/Ranking/RankingIdentityProviding.swift`). It is triggered **only at
world-ranking opt-in** and **degrades gracefully** (returns the anonymous UUID, never
crashes) if the capability/provider is not configured yet.

```swift
// TEMPLATE — new file, e.g. Sources/Services/Ranking/AppleSignInRankingIdentityProvider.swift
// Requires SPM product FirebaseAuth (Step 2) + the Sign in with Apple entitlement (§2.2).
import Foundation
import AuthenticationServices
import CryptoKit
import FirebaseAuth

/// Sign in with Apple → Firebase Auth. Conforms to `RankingIdentityProviding`: `accountId`
/// returns the Firebase `uid` once signed in, and otherwise falls back to a persisted
/// anonymous UUID so the ranking UI keeps working when auth is unavailable.
///
/// TRIGGER auth only from the world-ranking opt-in flow — never at app launch (§5.4:
/// nav / free-ride / personal ranking stay auth-free).
final class AppleSignInRankingIdentityProvider: NSObject, RankingIdentityProviding {

    /// Fallback identity so the app never crashes if Apple/Firebase auth isn't set up.
    private let fallback: RankingIdentityProviding

    init(fallback: RankingIdentityProviding = AnonymousRankingIdentityProvider()) {
        self.fallback = fallback
        super.init()
    }

    /// Never empty: signed-in Firebase uid, else the anonymous fallback id.
    var accountId: String {
        Auth.auth().currentUser?.uid ?? fallback.accountId
    }

    var isSignedIn: Bool { Auth.auth().currentUser != nil }

    /// Call from the opt-in button. Presents Apple, exchanges the credential with Firebase.
    /// Returns the Firebase uid on success; throws so the UI can show a non-fatal message.
    func signIn(presentationAnchor: ASPresentationAnchor) async throws -> String {
        let nonce = Self.randomNonce()
        let appleCredential = try await requestAppleCredential(
            nonce: Self.sha256(nonce),
            anchor: presentationAnchor
        )
        guard let tokenData = appleCredential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else {
            throw NSError(domain: "AppleSignIn", code: -1)
        }
        let credential = OAuthProvider.appleCredential(
            withIDToken: idToken,
            rawNonce: nonce,
            fullName: appleCredential.fullName
        )
        let result = try await Auth.auth().signIn(with: credential)
        return result.user.uid
    }

    /// Apple review 5.1.1(v): account deletion. Deletes leaderboard entries first
    /// (best-effort), then the Firebase user. Call from the in-app "delete account" control.
    func deleteAccount() async throws {
        // Delete leaderboards/*/entries/{uid} here (or via a Cloud Function) before:
        try await Auth.auth().currentUser?.delete()
    }

    // MARK: - ASAuthorization plumbing (nonce, presentation) — standard boilerplate.
    // Implement requestAppleCredential(nonce:anchor:) with ASAuthorizationController and a
    // continuation-backed ASAuthorizationControllerDelegate. randomNonce()/sha256() are the
    // canonical Firebase "Sign in with Apple" snippets.
    private func requestAppleCredential(
        nonce: String, anchor: ASPresentationAnchor
    ) async throws -> ASAuthorizationAppleIDCredential {
        // ... ASAuthorizationAppleIDProvider request + delegate bridged to async ...
        fatalError("Fill in with the standard ASAuthorizationController delegate bridge.")
    }

    private static func randomNonce(length: Int = 32) -> String {
        let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""; var remaining = length
        while remaining > 0 {
            var random: UInt8 = 0
            _ = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            if random < UInt8(chars.count) { result.append(chars[Int(random)]); remaining -= 1 }
        }
        return result
    }
    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
```

> Graceful-degradation contract: if the entitlement/provider isn't configured, `signIn`
> throws and the opt-in flow shows a "world ranking unavailable" message, while
> `accountId` keeps returning the anonymous UUID — no path force-unwraps auth state.

### 3.3 The single switch: flip Mock → Firestore

The mock is injected as a **default parameter** on the view-model initializer
(`Sources/Features/Navigation/NavigationDashboardViewModel.swift`):

```swift
init(
    ...,
    rankingIdentityProvider: RankingIdentityProviding = AnonymousRankingIdentityProvider(),
    rankingProfileStore: RankingProfileStoring = LocalRankingProfileStore(),
    worldRankingService: WorldRankingService = MockWorldRankingService()   // ← default = mock
) { ... }
```

The view model is constructed in exactly one place — `Sources/App/SeaNaviApp.swift`
around line 28 — and it currently **omits** `worldRankingService` (so it takes the mock
default). To go live, pass the real implementations there:

```swift
// SeaNaviApp.swift — the ONLY wiring change to flip the backend.
let viewModel = NavigationDashboardViewModel(
    locationService: service,
    weatherService: weatherService,
    rideLogSyncService: HealthWorkoutSyncService(),
    rankingIdentityProvider: AppleSignInRankingIdentityProvider(),   // was: default anonymous
    worldRankingService: FirestoreWorldRankingService()              // was: default mock
)
```

That is the entire switch: `isMockData` flips to `false`, the "mock data" banner in
`RankingView` disappears, and `worldRankingBoard(for:)` / `submitBest(...)` now talk to
Firestore. **This edit is out of scope for this task** (it touches app Swift code) — it is
documented here as the go-live action, to be done as its own reviewable commit after
Steps 1–7 pass. Keep it last so every prior stage is verified against the mock still in place.

---

## 4. Firestore security rules + indexes (author locally)

> Author these into the local files. They are deployed via the guarded wrapper in Step 5.
> Today `firestore.rules` is intentionally **deny-all** — replace that block with the rules
> below **only when you reach go-live**.

### 4.1 `firestore.rules` (replace the deny-all body)

```
rules_version = '2';
// leaderboards/{metric}/entries/{uid}
//  - public READ (leaderboard is public)
//  - owner-only WRITE (doc id must equal the signed-in uid)
//  - type/range validation on client-writable fields
//  - `verified` is server-only: clients may never set/change it (§4.4)
service cloud.firestore {
  match /databases/{database}/documents {
    match /leaderboards/{metric}/entries/{uid} {
      allow read: if true;

      allow create, update: if request.auth != null
        && request.auth.uid == uid
        && request.resource.data.userId == uid
        && request.resource.data.value is number
        && request.resource.data.value >= 0
        && request.resource.data.value <= 100000        // absolute sanity ceiling
        && request.resource.data.displayName is string
        && request.resource.data.displayName.size() >= 2
        && request.resource.data.displayName.size() <= 16
        // clients must NOT write `verified` (Cloud Functions owns it):
        && !(request.resource.data.keys().hasAny(['verified']));

      allow delete: if request.auth != null && request.auth.uid == uid;
    }
    // Everything else stays denied.
    match /{document=**} { allow read, write: if false; }
  }
}
```

> Tighter per-metric caps (e.g. speed ≤ 90 km/h per §4.2) are better enforced in the
> **Cloud Function** (Step 6), which can recompute; rules only do coarse type/range checks.

### 4.2 `firestore.indexes.json`

Reading Top-N `order(by:"value", descending:true)` on each `entries` subcollection uses
Firestore's automatic single-field index, so `indexes: []` is usually sufficient. If you
later add filtered/region queries (e.g. `whereField("region", ...).order(by:"value")`),
add the composite index here. The `count` aggregation in §3.1 needs no index.

---

## 5. Deploy — ONLY via the guarded wrapper

Never run a bare `firebase deploy`. `scripts/fb-deploy.sh` runs
`scripts/firebase-guard.sh` (verifies plist `PROJECT_ID`, `.firebaserc` default, and the
CLI's active project are all `ridelane`) and then forces `--project ridelane`.

```bash
# from repo root
scripts/fb-deploy.sh --only firestore:rules      # deploy security rules
scripts/fb-deploy.sh --only firestore:indexes    # deploy indexes
```

- If the guard fails with "active project is …", run `firebase use ridelane` and retry —
  do **not** bypass the wrapper.
- Deploy **rules before flipping the app** (Step 8): a live client against deny-all rules
  is safe (reads fail closed), but a live client against *missing* rules is not.

---

## 6. Cloud Functions — server-side validation (§4.4)

Client values are untrusted. A Cloud Function revalidates each submitted best and owns
the `verified` flag. Requires the **Blaze plan** (§1.4).

**Outline**
- Trigger: `onDocumentWritten("leaderboards/{metric}/entries/{uid}")`.
- Recompute / plausibility: clamp against per-metric caps (distance sane max; speed ≤ 90
  km/h per §4.2). Ideally recompute from a submitted GPS/activity summary (future: store a
  private, non-public ride summary the Function reads).
- Rate-limit: reject/flag more than N writes per uid per window.
- Outlier detection: flag values far beyond the current distribution.
- Set `verified: true` (or quarantine) using the Admin SDK — the only writer of that field.

**Starter template (TypeScript, `functions/src/index.ts`)**

```typescript
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { initializeApp } from "firebase-admin/app";

initializeApp();
const db = getFirestore();

// Per-metric plausibility ceilings (RANKING_MODE_PLAN.md §4.2).
const CAPS: Record<string, number> = { distance: 1000, topSpeed: 90 };
const MIN_SUBMIT_INTERVAL_MS = 5_000; // coarse rate-limit per uid/metric

export const validateLeaderboardEntry = onDocumentWritten(
  { document: "leaderboards/{metric}/entries/{uid}", region: "asia-northeast1" },
  async (event) => {
    const after = event.data?.after;
    if (!after?.exists) return; // deletion
    const metric = event.params.metric as string;
    const uid = event.params.uid as string;
    const data = after.data() as any;

    // Guard against Function re-trigger loops: skip if we already stamped it.
    if (data.validatedAt && data.verified !== undefined) return;

    const cap = CAPS[metric] ?? Number.MAX_SAFE_INTEGER;
    const value = typeof data.value === "number" ? data.value : -1;

    // Plausibility + basic rate limit.
    const now = Date.now();
    const lastMs = data.validatedAt?.toMillis?.() ?? 0;
    const tooFast = now - lastMs < MIN_SUBMIT_INTERVAL_MS;
    const plausible = value >= 0 && value <= cap && !tooFast;

    // TODO: recompute from a private ride summary + statistical outlier check here.

    await after.ref.set(
      {
        verified: plausible,       // server-only field (rules forbid clients writing it)
        validatedAt: FieldValue.serverTimestamp(),
        ...(plausible ? {} : { value: Math.min(Math.max(value, 0), cap) }),
      },
      { merge: true }
    );
  }
);
```

Deploy functions through the same guarded wrapper once written:

```bash
scripts/fb-deploy.sh --only functions
```

(Add a `"functions"` block to `firebase.json` and the `functions/` package first.)

---

## 7. Pre-flip verification (mock still wired)

Do this before Step 8 so problems surface without exposing users.

- `scripts/firebase-guard.sh` prints ✅ (project `ridelane` everywhere).
- Rules unit test / `firebase emulators:start` (Firestore + Auth): confirm owner-only
  write, public read, `verified` write from a client is **rejected**, out-of-range value
  is rejected.
- Build the app after Step 2/3 with the templates present but **not injected** — confirm
  it still compiles and the mock board still renders (regression baseline intact).

---

## 8. Flip the backend (see §3.3)

Make the single `SeaNaviApp.swift` edit from §3.3 (inject
`FirestoreWorldRankingService()` + `AppleSignInRankingIdentityProvider()`). Commit alone.
Rollback = revert that one commit; everything reverts to the mock with zero data risk.

---

## 9. Final verification checklist

- [ ] Firestore database exists in **`asia-northeast1`** (or chosen region) — location confirmed.
- [ ] Auth: Apple (and Google) providers enabled; Sign in with Apple entitlement present.
- [ ] Rules + indexes deployed via `scripts/fb-deploy.sh` (never bare `firebase deploy`).
- [ ] **Submit a score:** opt in → Sign in with Apple succeeds → register nickname →
      finish an eligible ride → `submitBest` writes `leaderboards/{metric}/entries/{uid}`.
- [ ] **Appears in board:** reopen ranking → own row shows with correct value, pinned/highlighted.
- [ ] **Server validation:** the Cloud Function set `verified` and clamped an out-of-range value.
- [ ] **Cross-device:** sign in with the same Apple ID on a second device → same `uid` →
      same rank/nickname (identity carried by `uid`, not device).
- [ ] **Anti-cheat sanity:** a client attempt to write `verified:true` or a value above the
      cap is rejected by rules and/or corrected by the Function.
- [ ] **Graceful degradation:** with auth misconfigured, the ranking screen shows a
      non-fatal "unavailable" state and does not crash; personal ranking still works.
- [ ] **Account deletion** (Apple 5.1.1(v)): in-app delete removes the entry + Firebase user.
- [ ] Privacy policy updated: public = nickname/value/achievedAt/region; GPS track stays private (§8.1).
- [ ] Blaze plan active + billing budget alert set.

---

## Guardrails recap (do not bypass)

- Deploy only via **`scripts/fb-deploy.sh`** → runs **`scripts/firebase-guard.sh`** →
  forces `--project ridelane`. Never `firebase deploy` directly.
- Create the Firestore database and enable auth providers **in the Console by hand**
  (live-mutating, location is irreversible) — not from CLI/MCP in this repo.
- `verified` is **server-only**: enforced by rules (client writes rejected) and owned by
  the Cloud Function.
- The Mock → Firestore flip is a **single, isolated** `SeaNaviApp.swift` edit — reversible
  by reverting one commit.
