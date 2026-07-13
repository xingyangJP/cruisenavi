import Foundation

/// Identity seam for world ranking. Returns a STABLE, unique account identifier used to
/// deduplicate a person across rides/devices and to pin their own row in the leaderboard.
///
/// Phase B (current): the only implementation is `AnonymousRankingIdentityProvider`, which
/// generates and persists a random UUID in `UserDefaults` (unique-per-install, testable).
///
/// The real production provider — **Sign in with Apple** — plugs in here later by returning its
/// stable `ASAuthorizationAppleIDCredential.user` value as `accountId`. No Apple auth, entitlement,
/// or `ASAuthorization` code exists yet; this protocol is the single seam where it will attach
/// (see RANKING_MODE_PLAN.md §5.3 / §5.4).
protocol RankingIdentityProviding {
    /// A stable identifier that is unique per account. Never empty.
    var accountId: String { get }
}

/// Capability add-on for identity providers backed by a real sign-in (Sign in with Apple →
/// Firebase Auth). The live `AppleSignInRankingIdentityProvider` conforms; the anonymous provider
/// deliberately does NOT, so the world-ranking UI treats "no auth provider" as "sign-in not
/// required" and the offline mock path is unchanged.
///
/// Reads/writes on the live board require `request.auth != null` (firestore.rules), so the UI must
/// drive `signIn()` before fetching or submitting. `deleteAccount()` satisfies App Store 5.1.1(v).
protocol RankingAuthProviding: RankingIdentityProviding {
    /// True once a real account session exists (Firebase `currentUser != nil`).
    var isSignedIn: Bool { get }

    /// Presents Sign in with Apple, exchanges the credential with Firebase Auth, and returns the
    /// Firebase `uid`. Throws (non-fatally) so the opt-in flow can show an "unavailable" message
    /// while `accountId` keeps returning the anonymous fallback.
    @discardableResult
    func signIn() async throws -> String

    /// Deletes the user's leaderboard entries (best-effort) and the Firebase user, then signs out.
    func deleteAccount() async throws
}

/// Local anonymous identity: a persisted random UUID. Unique per install, stable across launches,
/// and fully offline. Intended to be swapped for a Sign in with Apple provider before the world
/// ranking is connected to a live backend.
final class AnonymousRankingIdentityProvider: RankingIdentityProviding {
    static let defaultsKey = "ranking.anonymousAccountId"

    private let defaults: UserDefaults
    private let storageKey: String

    init(defaults: UserDefaults = .standard, storageKey: String = AnonymousRankingIdentityProvider.defaultsKey) {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    var accountId: String {
        if let existing = defaults.string(forKey: storageKey), !existing.isEmpty {
            return existing
        }
        let generated = UUID().uuidString
        defaults.set(generated, forKey: storageKey)
        return generated
    }
}
