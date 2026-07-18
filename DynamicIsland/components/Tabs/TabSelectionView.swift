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

import AtollExtensionKit
import SwiftUI
import Defaults
import AppKit
import UniformTypeIdentifiers

struct TabModel: Identifiable {
    let id: String
    let label: String
    let icon: String
    let view: NotchViews
    let experienceID: String?
    let accentColor: Color?

    init(label: String, icon: String, view: NotchViews, experienceID: String? = nil, accentColor: Color? = nil) {
        self.id = experienceID.map { "extension-\($0)" } ?? "system-\(view)-\(label)"
        self.label = label
        self.icon = icon
        self.view = view
        self.experienceID = experienceID
        self.accentColor = accentColor
    }
}

struct TabSelectionView: View {
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject private var extensionNotchExperienceManager = ExtensionNotchExperienceManager.shared
    @ObservedObject private var musicManager = MusicManager.shared
    @StateObject private var quickShareService = QuickShareService.shared
    @Default(.quickShareProvider) private var quickShareProvider
    @State private var showQuickSharePopover = false
    @Default(.enableTimerFeature) var enableTimerFeature
    @Default(.enableColorPickerFeature) var enableColorPickerFeature
    @Default(.timerDisplayMode) var timerDisplayMode
    @Default(.enableThirdPartyExtensions) private var enableThirdPartyExtensions
    @Default(.enableExtensionNotchExperiences) private var enableExtensionNotchExperiences
    @Default(.enableExtensionNotchTabs) private var enableExtensionNotchTabs
    @Default(.showCalendar) private var showCalendar
    @Default(.showMirror) private var showMirror
    @Default(.showStandardMediaControls) private var showStandardMediaControls
    @Default(.autoHideInactiveNotchMediaPlayer) private var autoHideInactiveNotchMediaPlayer
    @Default(.enableMinimalisticUI) private var enableMinimalisticUI
    @AppStorage("lingyu.topTabOrder.v1") private var storedTabOrder = ""
    @State private var isReordering = false
    @State private var draggedTabID: String?
    @State private var tabStripSuppressionToken = UUID()
    @Namespace var animation
    
    private var availableTabs: [TabModel] {
        var tabsArray: [TabModel] = []

        if homeTabVisible {
            tabsArray.append(TabModel(label: "Home", icon: "house.fill", view: .home))
        }

        if !enableMinimalisticUI {
            tabsArray.append(TabModel(label: "快捷", icon: "slider.horizontal.3", view: .productivity))
            if Defaults[.enableClipboardManager] {
                tabsArray.append(TabModel(label: "剪贴板", icon: "doc.on.clipboard", view: .clipboard))
            }
            if mediaTabVisible {
                tabsArray.append(TabModel(label: "媒体", icon: "play.circle.fill", view: .media))
            }
            tabsArray.append(TabModel(label: "APP", icon: "app.fill", view: .appFinder))
            tabsArray.append(TabModel(label: "Codex", icon: "sparkles", view: .llmUsage))
            // Keep the Pomodoro/timer page discoverable. When disabled, its
            // embedded empty state offers one-click enablement instead of making
            // the feature appear to have vanished.
            tabsArray.append(TabModel(label: "番茄钟", icon: "timer", view: .timer))
        }

        tabsArray.append(TabModel(label: "系统", icon: "chart.xyaxis.line", view: .stats))

        if Defaults[.dynamicShelf] {
            tabsArray.append(TabModel(label: "Shelf", icon: "tray.fill", view: .shelf))
        }

        if Defaults[.enableNotes] {
            tabsArray.append(TabModel(label: "Notes", icon: "note.text", view: .notes))
        }
        if Defaults[.enableTerminalFeature] {
            tabsArray.append(TabModel(label: "Terminal", icon: "apple.terminal", view: .terminal))
        }
        if extensionTabsEnabled {
            for payload in extensionTabPayloads {
                guard let tab = payload.descriptor.tab else { continue }
                let accent = payload.descriptor.accentColor.swiftUIColor
                let iconName = tab.iconSymbolName ?? "puzzlepiece.extension"
                tabsArray.append(
                    TabModel(
                        label: tab.title,
                        icon: iconName,
                        view: .extensionExperience,
                        experienceID: payload.descriptor.id,
                        accentColor: accent
                    )
                )
            }
        }
        return tabsArray
    }

    private var tabs: [TabModel] {
        let savedOrder = decodedStoredOrder
        guard !savedOrder.isEmpty else { return availableTabs }

        let positions = Dictionary(uniqueKeysWithValues: savedOrder.enumerated().map { ($0.element, $0.offset) })
        return availableTabs.enumerated().sorted { lhs, rhs in
            let left = positions[lhs.element.id] ?? (savedOrder.count + lhs.offset)
            let right = positions[rhs.element.id] ?? (savedOrder.count + rhs.offset)
            return left < right
        }.map(\.element)
    }
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(tabs) { tab in
                        tabItem(tab)
                            .id(tab.id)
                            .onDrop(
                                of: [UTType.plainText],
                                delegate: TabReorderDropDelegate(
                                    targetID: tab.id,
                                    draggedID: $draggedTabID,
                                    isEnabled: isReordering,
                                    move: moveTab,
                                    finish: finishReordering
                                )
                            )
                    }
                }
                .padding(.horizontal, 2)
            }
            .frame(maxWidth: .infinity)
            .clipShape(Capsule())
            .onChange(of: coordinator.currentView) { _, _ in
                scrollSelectedTabIntoView(using: proxy, animated: true)
            }
            .onAppear {
                scrollSelectedTabIntoView(using: proxy, animated: false)
            }
        }
        .animation(.smooth(duration: 0.3), value: coordinator.currentView)
        .animation(.smooth(duration: 0.2), value: isReordering)
        .onHover { hovering in
            coordinator.isTabStripInteractionActive = hovering
            vm.setScrollGestureSuppression(hovering, token: tabStripSuppressionToken)
        }
        .onAppear {
            ensureValidSelection(with: tabs)
            coordinator.updateAvailableTabViews(tabs.map(\.view))
        }
        .onChange(of: tabs.map(\.id)) { _, _ in
            ensureValidSelection(with: tabs)
            coordinator.updateAvailableTabViews(tabs.map(\.view))
        }
        .onDisappear {
            coordinator.isTabStripInteractionActive = false
            vm.setScrollGestureSuppression(false, token: tabStripSuppressionToken)
        }
    }

    @ViewBuilder
    private func tabItem(_ tab: TabModel) -> some View {
        let selected = isSelected(tab)
        let activeAccent = tab.accentColor ?? .white

        let button = TabButton(label: tab.label, icon: tab.icon, selected: selected) {
            if isReordering {
                finishReordering()
                return
            }
            if tab.view == .extensionExperience {
                coordinator.selectedExtensionExperienceID = tab.experienceID
            }
            coordinator.noteLiveActivityInteraction(for: tab.view)
            coordinator.currentView = tab.view
        }
        .frame(width: 36, height: 34)
        .foregroundStyle(selected ? activeAccent : .gray)
        .scaleEffect(isReordering ? 0.94 : 1)
        .overlay(alignment: .topTrailing) {
            if isReordering {
                Circle()
                    .fill(.orange)
                    .frame(width: 6, height: 6)
                    .offset(x: 1, y: -1)
            }
        }
        .background {
            if selected {
                Capsule()
                    .fill((tab.accentColor ?? Color(nsColor: .secondarySystemFill)).opacity(0.25))
                    .shadow(color: (tab.accentColor ?? .clear).opacity(0.4), radius: 8)
                    .matchedGeometryEffect(id: "capsule", in: animation)
            } else {
                Capsule()
                    .fill(Color.clear)
                    .matchedGeometryEffect(id: "capsule", in: animation)
                    .hidden()
            }
        }
        .onLongPressGesture(minimumDuration: 0.45) {
            guard !isReordering else { return }
            isReordering = true
            if Defaults[.enableHaptics] {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
        }

        if isReordering {
            button.onDrag {
                draggedTabID = tab.id
                return NSItemProvider(object: tab.id as NSString)
            }
        } else {
            button
        }
    }

    private var decodedStoredOrder: [String] {
        guard let data = storedTabOrder.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return ids
    }

    private func moveTab(_ draggedID: String, _ targetID: String) {
        guard draggedID != targetID else { return }
        var ids = tabs.map(\.id)
        guard let source = ids.firstIndex(of: draggedID),
              let destination = ids.firstIndex(of: targetID) else { return }

        withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.92)) {
            ids.move(
                fromOffsets: IndexSet(integer: source),
                toOffset: destination > source ? destination + 1 : destination
            )
            persistTabOrder(ids)
        }
    }

    private func finishReordering() {
        guard isReordering || draggedTabID != nil else { return }
        draggedTabID = nil
        isReordering = false
        if Defaults[.enableHaptics] {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    private func persistTabOrder(_ ids: [String]) {
        guard let data = try? JSONEncoder().encode(ids),
              let value = String(data: data, encoding: .utf8) else { return }
        storedTabOrder = value
    }

    private func scrollSelectedTabIntoView(using proxy: ScrollViewProxy, animated: Bool) {
        guard let selectedID = tabs.first(where: isSelected)?.id else { return }
        if animated {
            withAnimation(.smooth(duration: 0.28)) {
                proxy.scrollTo(selectedID, anchor: .center)
            }
        } else {
            proxy.scrollTo(selectedID, anchor: .center)
        }
    }

    private var extensionTabsEnabled: Bool {
        enableThirdPartyExtensions && enableExtensionNotchExperiences && enableExtensionNotchTabs
    }

    private var extensionTabPayloads: [ExtensionNotchExperiencePayload] {
        extensionNotchExperienceManager.activeExperiences.filter { $0.descriptor.tab != nil }
    }

    private var homeTabVisible: Bool {
        if enableMinimalisticUI {
            return true
        }
        return showCalendar || showMirror
    }

    private var mediaTabVisible: Bool {
        showStandardMediaControls
            && (!autoHideInactiveNotchMediaPlayer || musicManager.hasActiveSession)
    }

    private func isSelected(_ tab: TabModel) -> Bool {
        if tab.view == .extensionExperience {
            return coordinator.currentView == .extensionExperience
                && coordinator.selectedExtensionExperienceID == tab.experienceID
        }
        return coordinator.currentView == tab.view
    }

    private func ensureValidSelection(with tabs: [TabModel]) {
        guard !tabs.isEmpty else { return }
        if tabs.contains(where: { isSelected($0) }) {
            return
        }
        guard let first = tabs.first else { return }
        if first.view == .extensionExperience {
            coordinator.selectedExtensionExperienceID = first.experienceID
        } else {
            coordinator.selectedExtensionExperienceID = nil
        }
        coordinator.currentView = first.view
    }
}

private struct TabReorderDropDelegate: DropDelegate {
    let targetID: String
    @Binding var draggedID: String?
    let isEnabled: Bool
    let move: (String, String) -> Void
    let finish: () -> Void

    func dropEntered(info: DropInfo) {
        guard isEnabled, let draggedID else { return }
        move(draggedID, targetID)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard isEnabled else { return false }
        finish()
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        isEnabled ? DropProposal(operation: .move) : nil
    }
}

#Preview {
    DynamicIslandHeader().environmentObject(DynamicIslandViewModel())
}
