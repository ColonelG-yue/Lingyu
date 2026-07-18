import XCTest

final class DynamicIslandUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "--uitesting",
            "-firstLaunch", "NO",
            "-enableMinimalisticUI", "NO",
            "-showCalendar", "YES",
            "-showStandardMediaControls", "YES",
            "-autoHideInactiveNotchMediaPlayer", "NO"
        ]
        app.launch()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    // App launches and stays alive without crashing.
    func testAppLaunchesWithoutCrashing() throws {
        let isRunning = app.wait(for: .runningForeground, timeout: 10.0)
            || app.wait(for: .runningBackground, timeout: 10.0)
        XCTAssertTrue(isRunning, "App should be running after launch.")
        XCTAssertNotEqual(app.state, .notRunning, "App should not have terminated.")
    }

    // The notch panel is present and exposed to accessibility.
    func testNotchExpansion() throws {
        let notch = app.images["AtollNotch"].firstMatch
        XCTAssertTrue(notch.waitForExistence(timeout: 15.0), "The Atoll notch should be visible.")
    }

    // Core custom tabs remain reachable and the quick page exposes real actions.
    func testPrimaryTabsAndQuickActions() throws {
        let notch = app.images["AtollNotch"].firstMatch
        XCTAssertTrue(notch.waitForExistence(timeout: 15.0))

        let quickTab = app.descendants(matching: .any)["Atoll.Tab.快捷"]
        XCTAssertTrue(quickTab.waitForExistence(timeout: 5.0))
        XCTAssertTrue(app.descendants(matching: .any)["Atoll.Tab.APP"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["Atoll.Tab.Codex"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["Atoll.Tab.系统"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["Atoll.Tab.剪贴板"].exists)
        XCTAssertTrue(
            app.descendants(matching: .any)["Atoll.Tab.番茄钟"].exists,
            "The Pomodoro tab must remain reachable even when it is outside the initial visible strip."
        )

        quickTab.click()
        XCTAssertTrue(app.descendants(matching: .any)["Atoll.QuickAction.番茄钟 25 分钟"].waitForExistence(timeout: 3.0))
        XCTAssertTrue(app.descendants(matching: .any)["Atoll.QuickAction.临时笔记"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["Atoll.QuickAction.系统监控"].exists)
        XCTAssertFalse(
            app.descendants(matching: .any)["Atoll.QuickAction.清空剪贴板"].exists,
            "Clipboard history must not be destructively cleared from Quick Controls."
        )
    }
}
