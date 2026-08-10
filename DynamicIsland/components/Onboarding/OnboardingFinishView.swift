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

import SwiftUI

struct OnboardingFinishView: View {
    let onFinish: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)
                .padding()

            Text("灵屿已经准备好了")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("你可以直接使用灵屿，也可以随时进入设置中心调整外观、手势、权限和顶部功能。")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Spacer()
            Spacer()

            VStack(spacing: 12) {
                Button(action: onOpenSettings) {
                    Label("打开设置中心", systemImage: "gear")
                        .controlSize(.large)
                }
                .controlSize(.large)

                Button("完成", action: onFinish)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                
                // Privacy Policy Link
                Button(action: {
                    if let url = URL(string: "https://ebullioscopic.github.io/DynamicIsland/privacy-policy") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Text("隐私政策")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
        )
    }
}

#Preview {
    OnboardingFinishView(onFinish: { }, onOpenSettings: { })
}
