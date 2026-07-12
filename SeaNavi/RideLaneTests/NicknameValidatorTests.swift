import XCTest
@testable import RideLane

final class NicknameValidatorTests: XCTestCase {

    func testValidNicknameTrimsWhitespace() {
        let result = NicknameValidator.validate("  Rider42  ")
        XCTAssertEqual(try? result.get(), "Rider42")
        XCTAssertTrue(NicknameValidator.isValid("Rider42"))
    }

    func testValidJapaneseAndAllowedPunctuation() {
        XCTAssertEqual(try? NicknameValidator.validate("山田_太郎").get(), "山田_太郎")
        XCTAssertEqual(try? NicknameValidator.validate("cool-rider 7").get(), "cool-rider 7")
    }

    func testEmptyOrWhitespaceOnly() {
        XCTAssertEqual(failure(NicknameValidator.validate("")), .empty)
        XCTAssertEqual(failure(NicknameValidator.validate("     ")), .empty)
    }

    func testTooShort() {
        XCTAssertEqual(failure(NicknameValidator.validate("a")), .tooShort)
        // Trimming first: a single char surrounded by spaces is still too short.
        XCTAssertEqual(failure(NicknameValidator.validate("  x ")), .tooShort)
    }

    func testTooLong() {
        let long = String(repeating: "a", count: NicknameValidator.maxLength + 1)
        XCTAssertEqual(failure(NicknameValidator.validate(long)), .tooLong)
    }

    func testMaxLengthBoundaryIsValid() {
        let exactly = String(repeating: "a", count: NicknameValidator.maxLength)
        XCTAssertTrue(NicknameValidator.isValid(exactly))
    }

    func testInvalidCharacters() {
        XCTAssertEqual(failure(NicknameValidator.validate("bad!name")), .invalidCharacters)
        XCTAssertEqual(failure(NicknameValidator.validate("rider😀")), .invalidCharacters)
        XCTAssertEqual(failure(NicknameValidator.validate("a@b")), .invalidCharacters)
    }

    func testReservedAndImpersonationWords() {
        XCTAssertEqual(failure(NicknameValidator.validate("RideLane")), .reserved)
        XCTAssertEqual(failure(NicknameValidator.validate("ridelane_fan")), .reserved)
        XCTAssertEqual(failure(NicknameValidator.validate("admin")), .reserved)
        XCTAssertEqual(failure(NicknameValidator.validate("公式アカウント")), .reserved)
        XCTAssertEqual(failure(NicknameValidator.validate("運営")), .reserved)
    }

    func testProfanityBlocked() {
        XCTAssertEqual(failure(NicknameValidator.validate("fuckrider")), .reserved)
        XCTAssertEqual(failure(NicknameValidator.validate("死ね")), .reserved)
    }

    func testReservedIsCaseInsensitive() {
        XCTAssertEqual(failure(NicknameValidator.validate("ADMIN")), .reserved)
        XCTAssertEqual(failure(NicknameValidator.validate("RiDeLaNe")), .reserved)
    }

    /// Whole-word matching for short ASCII official words must not reject legitimate names that
    /// merely embed them (Scunthorpe problem).
    func testWordEmbeddingOfficialTokenIsAllowed() {
        XCTAssertTrue(NicknameValidator.isValid("Badminton"))   // embeds "admin"
        XCTAssertTrue(NicknameValidator.isValid("Supporter"))   // embeds "support"
        XCTAssertTrue(NicknameValidator.isValid("Moderation"))  // embeds "moderator" prefix
    }

    /// …but the official words remain blocked as standalone tokens (impersonation).
    func testOfficialTokenAsWholeWordIsBlocked() {
        XCTAssertEqual(failure(NicknameValidator.validate("Support")), .reserved)
        XCTAssertEqual(failure(NicknameValidator.validate("admin_fan")), .reserved)
        XCTAssertEqual(failure(NicknameValidator.validate("official-1")), .reserved)
    }

    /// NFD (decomposed) input must validate the same as its precomposed NFC form.
    func testDecomposedUnicodeIsNormalizedAndAccepted() {
        // "が" as か (U+304B) + combining dakuten (U+3099) → should be accepted and returned as NFC.
        let nfd = "\u{304B}\u{3099}\u{3070}"  // が + ば, decomposed
        let result = NicknameValidator.validate(nfd)
        XCTAssertEqual(try? result.get(), nfd.precomposedStringWithCanonicalMapping)
        // Accented Latin decomposed: "e" + U+0301 twice → "éé".
        XCTAssertTrue(NicknameValidator.isValid("e\u{0301}e\u{0301}"))
    }

    // MARK: - Helper

    private func failure(_ result: Result<String, NicknameValidationError>) -> NicknameValidationError? {
        if case let .failure(error) = result { return error }
        return nil
    }
}
