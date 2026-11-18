import ARJOCore
import XCTest
@testable import ARJOUI

@MainActor
final class ParentalControlTests: XCTestCase {
    private let profileID = UUID()
    private let pins = FakePINStore()
    private var now = Date(timeIntervalSince1970: 1_792_859_400)
    private lazy var settings = SettingsModel(repository: NullSettingsRepository(), debounce: .seconds(60))

    private func makeControl(profile: UUID? = nil) -> ParentalControl {
        ParentalControl(profileID: profile ?? profileID, settings: settings, pinStore: pins, clock: { [unowned self] in self.now })
    }

    func testNothingIsLockedWithoutPIN() {
        let control = makeControl()
        control.setMarkedLocked(true, area: .live, group: "Erwachsene")
        XCTAssertFalse(control.hasPIN)
        XCTAssertFalse(control.isLocked(.live, "Erwachsene"))
        XCTAssertTrue(control.isMarkedLocked(.live, "Erwachsene"))
    }

    func testMarkedGroupsAreLockedPerAreaAndProfile() {
        let control = makeControl()
        XCTAssertTrue(control.setPIN("1234"))
        control.setMarkedLocked(true, area: .movie, group: "FSK 18")

        XCTAssertTrue(control.isLocked(.movie, "FSK 18"))
        XCTAssertFalse(control.isLocked(.series, "FSK 18"))
        XCTAssertFalse(control.isLocked(.movie, "Komödie"))
        XCTAssertFalse(control.isLocked(.movie, nil))
        XCTAssertFalse(makeControl(profile: UUID()).isLocked(.movie, "FSK 18"))

        control.setMarkedLocked(false, area: .movie, group: "FSK 18")
        XCTAssertFalse(control.isLocked(.movie, "FSK 18"))
    }

    func testUnlockWithCorrectPINOpensGroupsUntilExpiryOrRelock() {
        let control = makeControl()
        _ = control.setPIN("1234")
        control.setMarkedLocked(true, area: .live, group: "Erwachsene")
        control.requestUnlock()
        XCTAssertTrue(control.isPromptingPIN)

        XCTAssertFalse(control.unlock(pin: "0000"))
        XCTAssertEqual(control.errorMessage, "Falsche PIN.")
        XCTAssertTrue(control.isLocked(.live, "Erwachsene"))

        XCTAssertTrue(control.unlock(pin: "1234"))
        XCTAssertFalse(control.isPromptingPIN)
        XCTAssertFalse(control.isLocked(.live, "Erwachsene"))

        now = now.addingTimeInterval(ParentalControl.unlockDuration + 1)
        XCTAssertTrue(control.isLocked(.live, "Erwachsene"), "nach Ablauf wieder gesperrt")

        now = now.addingTimeInterval(-ParentalControl.unlockDuration)
        XCTAssertFalse(control.isLocked(.live, "Erwachsene"))
        control.lockNow()
        XCTAssertTrue(control.isLocked(.live, "Erwachsene"))
    }

    func testTooManyWrongAttemptsLockTheInputTemporarily() {
        let control = makeControl()
        _ = control.setPIN("1234")
        for _ in 0..<ParentalControl.maxFailedAttempts { XCTAssertFalse(control.verify("9999")) }

        XCTAssertNotNil(control.lockoutRemaining)
        XCTAssertFalse(control.verify("1234"), "auch die richtige PIN wird während der Sperre abgelehnt")
        XCTAssertEqual(control.errorMessage, "Zu viele Versuche. Bitte warte kurz.")

        now = now.addingTimeInterval(ParentalControl.lockoutDuration + 1)
        XCTAssertNil(control.lockoutRemaining)
        XCTAssertTrue(control.verify("1234"))
    }

    func testPINValidationAndManagement() {
        let control = makeControl()
        XCTAssertFalse(control.setPIN("12"))
        XCTAssertFalse(control.setPIN("12ab"))
        XCTAssertEqual(control.errorMessage, "Die PIN muss 4 bis 6 Ziffern haben.")
        XCTAssertTrue(control.setPIN("123456"))
        XCTAssertTrue(control.hasPIN)

        XCTAssertFalse(control.changePIN(current: "0000", new: "5555"))
        XCTAssertTrue(control.changePIN(current: "123456", new: "5555"))
        XCTAssertTrue(control.verify("5555"))

        XCTAssertFalse(control.removePIN(current: "1111"))
        XCTAssertTrue(control.hasPIN)
        XCTAssertTrue(control.removePIN(current: "5555"))
        XCTAssertFalse(control.hasPIN)
    }

    func testUnreadablePINStateFailsClosed() {
        pins.failOnRead = true
        XCTAssertTrue(makeControl().hasPIN, "im Zweifel gesperrt lassen")
    }
}
