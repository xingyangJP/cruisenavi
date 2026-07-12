import Foundation

/// The user's world-ranking profile: a display nickname bound to a stable account id.
///
/// The nickname is **non-unique by design** (RANKING_MODE_PLAN.md §5.4): duplicates are allowed and
/// identity is carried entirely by `accountId` (from `RankingIdentityProviding`). There is no
/// reservation, uniqueness check, or rename cooldown.
struct RankingProfile: Codable, Equatable {
    let nickname: String
    let accountId: String
}

/// Validation outcome for a candidate nickname. `.message` is the user-facing, localized reason.
enum NicknameValidationError: Error, Equatable {
    case empty
    case tooShort
    case tooLong
    case invalidCharacters
    case reserved

    var message: String {
        switch self {
        case .empty:
            return L10n.tr("ニックネームを入力してください")
        case .tooShort:
            return L10n.format("ニックネームは%d文字以上で入力してください", NicknameValidator.minLength)
        case .tooLong:
            return L10n.format("ニックネームは%d文字以内で入力してください", NicknameValidator.maxLength)
        case .invalidCharacters:
            return L10n.tr("使用できない文字が含まれています")
        case .reserved:
            return L10n.tr("そのニックネームは使用できません")
        }
    }
}

/// Pure, deterministic nickname validation. No I/O, no globals — safe to unit test directly.
///
/// Rules (RANKING_MODE_PLAN.md §5.4):
/// 1. Trim surrounding whitespace.
/// 2. Length must be within `[minLength, maxLength]` (counted in Characters / grapheme clusters).
/// 3. Allowed characters only: letters (incl. CJK), digits, space, and a small punctuation set
///    (`_`, `-`). Control characters, emoji, and symbols are rejected. Input is normalized to NFC
///    first so canonically-equivalent NFD (decomposed) forms are accepted.
/// 4. Reserved / impersonation / profanity block:
///    - Short ASCII official words ("admin", "official", …) are matched on **word boundaries**
///      (our `_`/`-`/space separators), so legitimate names embedding them ("Badminton",
///      "Supporter") are NOT rejected — the Scunthorpe problem.
///    - Brand/CJK terms and profanity are matched case-insensitively as **substrings**
///      (so "ridelane_fan" and "fuckrider" are still blocked).
enum NicknameValidator {
    static let minLength = 2
    static let maxLength = 16

    /// Short ASCII official/impersonation words. Matched only as whole tokens (split on
    /// space/`_`/`-`), so `Badminton`/`Supporter`/`Moderation` are allowed while `admin`,
    /// `admin_fan`, `official-1` are blocked.
    static let wholeWordBlockedWords: [String] = [
        "admin", "administrator", "moderator", "official", "support"
    ]

    /// Brand names, CJK impersonation terms, and profanity. Matched case-insensitively as
    /// substrings against the trimmed, lowercased nickname.
    static let substringBlockedWords: [String] = [
        // Brand / impersonation
        "ridelane", "運営", "公式", "管理者",
        // Small profanity list
        "fuck", "shit", "bitch", "asshole", "死ね", "殺す"
    ]

    /// Backwards-compatible flat view of every blocked token (both match strategies).
    static var blockedWords: [String] { wholeWordBlockedWords + substringBlockedWords }

    /// Validates and normalizes a raw nickname. On success returns the trimmed nickname to persist.
    static func validate(_ raw: String) -> Result<String, NicknameValidationError> {
        // Normalize to NFC so decomposed (NFD) input — e.g. a dakuten kana or accented Latin
        // letter pasted as base + combining mark — is treated the same as its precomposed form.
        let normalized = raw.precomposedStringWithCanonicalMapping
        let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return .failure(.empty)
        }
        if trimmed.count < minLength {
            return .failure(.tooShort)
        }
        if trimmed.count > maxLength {
            return .failure(.tooLong)
        }
        if !isAllowedCharacterSet(trimmed) {
            return .failure(.invalidCharacters)
        }
        if containsBlockedWord(trimmed) {
            return .failure(.reserved)
        }
        return .success(trimmed)
    }

    /// Convenience boolean form.
    static func isValid(_ raw: String) -> Bool {
        if case .success = validate(raw) { return true }
        return false
    }

    // MARK: - Rules

    private static func isAllowedCharacterSet(_ value: String) -> Bool {
        for scalar in value.unicodeScalars {
            if CharacterSet.letters.contains(scalar) { continue }
            if CharacterSet.decimalDigits.contains(scalar) { continue }
            if scalar == " " || scalar == "_" || scalar == "-" { continue }
            return false
        }
        return true
    }

    private static func containsBlockedWord(_ value: String) -> Bool {
        let lowered = value.lowercased()

        // Substring match: brand/CJK terms and profanity.
        if substringBlockedWords.contains(where: { !$0.isEmpty && lowered.contains($0) }) {
            return true
        }

        // Whole-token match: short ASCII official words split on our separators, so words that
        // merely embed them (e.g. "badminton" containing "admin") are allowed.
        let tokens = lowered.split(whereSeparator: { $0 == " " || $0 == "_" || $0 == "-" })
        let tokenSet = Set(tokens.map(String.init))
        return wholeWordBlockedWords.contains { !$0.isEmpty && tokenSet.contains($0) }
    }
}

/// Local persistence for the `RankingProfile`. Stored in `UserDefaults` (same store the anonymous
/// identity UUID uses). No networking. The published/registration flow lives in the view model /
/// UI layer; this store is the pure read/write seam.
protocol RankingProfileStoring {
    func load() -> RankingProfile?
    func save(_ profile: RankingProfile)
    func clear()
}

final class LocalRankingProfileStore: RankingProfileStoring {
    static let defaultsKey = "ranking.profile"

    private let defaults: UserDefaults
    private let storageKey: String

    init(defaults: UserDefaults = .standard, storageKey: String = LocalRankingProfileStore.defaultsKey) {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    func load() -> RankingProfile? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(RankingProfile.self, from: data)
    }

    func save(_ profile: RankingProfile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        defaults.set(data, forKey: storageKey)
    }

    func clear() {
        defaults.removeObject(forKey: storageKey)
    }
}
