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
import AVFoundation
import Defaults

enum OnboardingStep {
    case welcome
    case cameraPermission
    case calendarPermission
    case musicPermission
    case profileSelection
    case finished
}

private let calendarService = CalendarService()

struct OnboardingView: View {
    @State private var step: OnboardingStep = .welcome
    @State private var showFocusMonitoringChoice = false
    @State private var didPresentFocusMonitoringChoice = false
    let onFinish: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        ZStack {
            switch step {
            case .welcome:
                WelcomeView {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        step = .cameraPermission
                    }
                }
                .transition(.opacity)

            case .cameraPermission:
                PermissionRequestView(
                    icon: Image(systemName: "camera.fill"),
                    title: "允许使用摄像头",
                    description: "灵屿可以在刘海区域显示镜子预览。只有开启镜子功能时才会使用摄像头，你也可以之后在设置中关闭。",
                    privacyNote: "未经允许不会使用摄像头，也不会录制或保存画面。",
                    onAllow: {
                        Task {
                            await requestCameraPermission()
                            withAnimation(.easeInOut(duration: 0.6)) {
                                step = .calendarPermission
                            }
                        }
                    },
                    onSkip: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            step = .calendarPermission
                        }
                    }
                )
                .transition(.opacity)

            case .calendarPermission:
                PermissionRequestView(
                    icon: Image(systemName: "calendar"),
                    title: "允许读取日历",
                    description: "灵屿可以把 Mac 日历中的近期日程显示在刘海里。日历权限只用于读取和展示你的日程。",
                    privacyNote: "日历数据只保存在本机使用，不会上传或分享。",
                    onAllow: {
                        Task {
                            await requestCalendarPermission()
                            withAnimation(.easeInOut(duration: 0.6)) {
                                step = .musicPermission
                            }
                        }
                    },
                    onSkip: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            step = .musicPermission
                        }
                    }
                )
                .transition(.opacity)
                
            case .musicPermission:
                MusicControllerSelectionView(
                    onContinue: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            step = .profileSelection
                        }
                    }
                )
                .transition(.opacity)
                
            case .profileSelection:
                ProfileSelectionView(
                    onContinue: { profiles in
                        applyProfileSettings(profiles)
                        withAnimation(.easeInOut(duration: 0.6)) {
                            step = .finished
                        }
                    }
                )
                .transition(.opacity)

            case .finished:
                OnboardingFinishView(onFinish: onFinish, onOpenSettings: onOpenSettings)
            }
        }
        .frame(width: 400, height: 600)
        .onAppear {
            guard !didPresentFocusMonitoringChoice else { return }
            didPresentFocusMonitoringChoice = true
            showFocusMonitoringChoice = true
        }
        .confirmationDialog(
            "专注检测方式",
            isPresented: $showFocusMonitoringChoice,
            titleVisibility: .visible
        ) {
            Button("使用 DevTools") {
                Defaults[.focusMonitoringMode] = .useDevTools
            }

            Button("不使用 DevTools") {
                Defaults[.focusMonitoringMode] = .withoutDevTools
            }

            Button("稍后设置", role: .cancel) {}
        } message: {
            Text("这是可选功能，之后可以在菜单栏或设置中心中修改。")
        }
    }

    // MARK: - Permission Request Logic

    func requestCameraPermission() async {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    func requestCalendarPermission() async {
        await calendarService.requestAccess()
    }
}
