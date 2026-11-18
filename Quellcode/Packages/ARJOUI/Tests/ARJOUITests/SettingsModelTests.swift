import ARJOCore
import XCTest
@testable import ARJOUI

private final class FakeSettingsRepository: SettingsRepository, @unchecked Sendable {
    var stored = AppSettings()
    var saved: [AppSettings] = []
    var failOnLoad = false
    var failOnSave = false

    func load() async throws -> AppSettings {
        if failOnLoad { throw URLError(.cannotOpenFile) }
        return stored
    }

    func save(_ settings: AppSettings) async throws {
        if failOnSave { throw URLError(.cannotWriteToFile) }
        saved.append(settings)
    }
}

@MainActor
final class SettingsModelTests: XCTestCase {
    private let repository = FakeSettingsRepository()

    private func waitUntil(_ condition: @MainActor () -> Bool, line: UInt = #line) async {
        for _ in 0..<5_000 where !condition() { await Task.yield() }
        XCTAssertTrue(condition(), "Bedingung wurde nicht erreicht", line: line)
    }

    func testLoadAppliesStoredSettingsWithoutWritingThemBack() async {
        repository.stored.accent = .blue
        let model = SettingsModel(repository: repository, debounce: .zero)

        await model.load()
        for _ in 0..<100 { await Task.yield() }

        XCTAssertEqual(model.settings.accent, .blue)
        XCTAssertTrue(repository.saved.isEmpty)
    }

    func testChangesAreSavedAndRapidChangesCollapse() async {
        let model = SettingsModel(repository: repository, debounce: .milliseconds(30))
        await model.load()

        model.settings.epgOffsetMinutes = 30
        model.settings.epgOffsetMinutes = 60
        model.settings.aspect = .fill

        await waitUntil { !self.repository.saved.isEmpty }
        XCTAssertEqual(repository.saved.last?.epgOffsetMinutes, 60)
        XCTAssertEqual(repository.saved.last?.aspect, .fill)
        XCTAssertEqual(repository.saved.count, 1)
    }

    func testFlushSavesImmediately() async {
        let model = SettingsModel(repository: repository, debounce: .seconds(60))
        await model.load()
        model.settings.autoRefresh = false

        await model.flush()

        XCTAssertEqual(repository.saved.last?.autoRefresh, false)
    }

    func testFailuresAreReported() async {
        repository.failOnLoad = true
        let model = SettingsModel(repository: repository, debounce: .zero)
        await model.load()
        XCTAssertEqual(model.errorMessage, "Die Einstellungen konnten nicht gelesen werden. Es gelten die Standardwerte.")
        model.dismissError()

        repository.failOnSave = true
        model.settings.accent = .red
        await model.flush()
        XCTAssertEqual(model.errorMessage, "Die Einstellungen konnten nicht gespeichert werden.")
    }

    func testTimeZoneAndOffsetHelpers() {
        var settings = AppSettings()
        XCTAssertEqual(settings.timeZone, .current)
        settings.timeZoneID = "Asia/Tokyo"
        XCTAssertEqual(settings.timeZone.identifier, "Asia/Tokyo")
        settings.timeZoneID = "Kein/Ort"
        XCTAssertEqual(settings.timeZone, .current)
        settings.epgOffsetMinutes = -90
        XCTAssertEqual(settings.epgOffset, -5_400)
    }
}
