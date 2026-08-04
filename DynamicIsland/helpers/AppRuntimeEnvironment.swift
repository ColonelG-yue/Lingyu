/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import Foundation

/// Runtime context flags used to keep the app's launch deterministic on CI.
enum AppRuntimeEnvironment {
    /// `true` only in DEBUG builds launched by XCUITest (`--uitesting`); always false in Release.
    static let isUITesting: Bool = {
        #if DEBUG
        return CommandLine.arguments.contains("--uitesting")
        #else
        return false
        #endif
    }()

    /// Allows the dedicated persistence regression test to exercise the same
    /// restore path used by production launches. Other UI tests remain isolated
    /// from previously persisted navigation state.
    static let restoresPageMemoryDuringUITesting: Bool = {
        #if DEBUG
        return CommandLine.arguments.contains("--uitesting-page-memory")
        #else
        return false
        #endif
    }()

    /// Resets only the UI-test app's page memory before a persistence test.
    static let resetsPageMemoryDuringUITesting: Bool = {
        #if DEBUG
        return CommandLine.arguments.contains("--reset-page-memory")
        #else
        return false
        #endif
    }()

    /// Enables lightweight trackpad diagnostics without changing production
    /// behavior. Useful when checking terminal vertical scrolling versus tab
    /// switching on a real device.
    static let gestureDiagnosticsEnabled: Bool = {
        #if DEBUG
        return CommandLine.arguments.contains("--lingyu-gesture-diagnostics")
        #else
        return false
        #endif
    }()

    static let runsActivityPriorityFixture: Bool = {
        #if DEBUG
        return CommandLine.arguments.contains("--uitesting-activity-priority")
        #else
        return false
        #endif
    }()
}
