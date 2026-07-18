/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
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

import AppKit
import SwiftUI

struct TabButton: View {
    let label: String
    let icon: String
    let selected: Bool
    let onClick: () -> Void
    
    var body: some View {
        Button(action: onClick) {
            Group {
                if label == "APP" {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: "/System/Applications/App Store.app"))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 25, height: 25)
                        .shadow(color: .black.opacity(0.28), radius: 2, y: 1)
                        .accessibilityLabel("应用程序")
                } else {
                    Image(systemName: icon)
                }
            }
                .contentShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityIdentifier("Atoll.Tab.\(label)")
    }
}

#Preview {
    TabButton(label: "Home", icon: "tray.fill", selected: true) {
        print("Tapped")
    }
}
