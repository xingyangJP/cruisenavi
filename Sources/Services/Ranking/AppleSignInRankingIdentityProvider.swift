import Foundation
import AuthenticationServices
import CryptoKit
import UIKit
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore

/// Sign in with Apple → Firebase Auth. Conforms to `RankingAuthProviding`: `accountId` returns the
/// Firebase `uid` once signed in, and otherwise falls back to a persisted anonymous UUID so the app
/// never crashes when auth is unavailable/misconfigured.
///
/// TRIGGER auth only from the world-ranking opt-in flow — never at app launch (§5.4: nav / free-ride
/// / personal ranking stay auth-free). Graceful degradation contract: if the entitlement/provider is
/// not configured, `signIn()` throws (the UI shows "world ranking unavailable") while `accountId`
/// keeps returning the anonymous fallback — no path force-unwraps auth state.
final class AppleSignInRankingIdentityProvider: NSObject, RankingAuthProviding {

    /// Fallback identity so the app never crashes if Apple/Firebase auth isn't set up.
    private let fallback: RankingIdentityProviding

    /// Held only for the duration of one presentation (bridges the delegate callback → async).
    private var authContinuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?
    /// Strong-holds the in-flight controller so it isn't deallocated mid-presentation.
    private var activeController: ASAuthorizationController?

    init(fallback: RankingIdentityProviding = AnonymousRankingIdentityProvider()) {
        self.fallback = fallback
        super.init()
    }

    /// Firebase Auth, but only when the app is actually configured. Guarding on `FirebaseApp.app()`
    /// keeps `accountId`/`isSignedIn` from crashing (`Auth.auth()` requires a configured app) when
    /// the backend isn't provisioned yet — the graceful-degradation contract.
    private var auth: Auth? {
        FirebaseApp.app() != nil ? Auth.auth() : nil
    }

    /// Never empty: signed-in Firebase uid, else the anonymous fallback id.
    var accountId: String {
        auth?.currentUser?.uid ?? fallback.accountId
    }

    var isSignedIn: Bool { auth?.currentUser != nil }

    /// Presents Apple, exchanges the credential with Firebase, returns the Firebase uid.
    @discardableResult
    func signIn() async throws -> String {
        guard let auth else {
            throw NSError(domain: "AppleSignIn", code: -3,
                          userInfo: [NSLocalizedDescriptionKey: "Firebase is not configured"])
        }
        let rawNonce = Self.randomNonce()
        let appleCredential = try await requestAppleCredential(hashedNonce: Self.sha256(rawNonce))

        guard let tokenData = appleCredential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else {
            throw NSError(domain: "AppleSignIn", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Apple identity token missing"])
        }

        let credential = OAuthProvider.appleCredential(
            withIDToken: idToken,
            rawNonce: rawNonce,
            fullName: appleCredential.fullName
        )
        let result = try await auth.signIn(with: credential)
        return result.user.uid
    }

    /// App Store 5.1.1(v): account deletion. Deletes the user's leaderboard entries (best-effort)
    /// across every metric, then the Firebase user, then signs out. A `requiresRecentLogin` error
    /// from `user.delete()` propagates so the UI can prompt a fresh sign-in.
    func deleteAccount() async throws {
        guard let auth, let user = auth.currentUser else { return }
        let uid = user.uid
        let db = Firestore.firestore()
        for metric in RankingMetric.allCases {
            try? await db.collection("leaderboards")
                .document(metric.firestoreMetricId)
                .collection("entries")
                .document(uid)
                .delete()
        }
        try await user.delete()
        try? auth.signOut()
    }

    // MARK: - ASAuthorization plumbing

    @MainActor
    private func requestAppleCredential(hashedNonce: String) async throws -> ASAuthorizationAppleIDCredential {
        try await withCheckedThrowingContinuation { continuation in
            self.authContinuation = continuation
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName]
            request.nonce = hashedNonce
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            self.activeController = controller
            controller.performRequests()
        }
    }

    private func finish(with result: Result<ASAuthorizationAppleIDCredential, Error>) {
        let continuation = authContinuation
        authContinuation = nil
        activeController = nil
        switch result {
        case .success(let credential): continuation?.resume(returning: credential)
        case .failure(let error): continuation?.resume(throwing: error)
        }
    }

    // MARK: - Nonce helpers (canonical Firebase "Sign in with Apple" snippets)

    private static func randomNonce(length: Int = 32) -> String {
        let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var random: UInt8 = 0
            _ = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            if random < UInt8(chars.count) {
                result.append(chars[Int(random)])
                remaining -= 1
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

extension AppleSignInRankingIdentityProvider: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
            finish(with: .success(credential))
        } else {
            finish(with: .failure(NSError(
                domain: "AppleSignIn", code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Unexpected Apple credential type"]
            )))
        }
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        finish(with: .failure(error))
    }
}

extension AppleSignInRankingIdentityProvider: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let activeScene = UIApplication.shared.connectedScenes
            .first { $0.activationState == .foregroundActive } as? UIWindowScene
        let anyScene = activeScene ?? UIApplication.shared.connectedScenes.first as? UIWindowScene
        return anyScene?.keyWindow ?? ASPresentationAnchor()
    }
}
