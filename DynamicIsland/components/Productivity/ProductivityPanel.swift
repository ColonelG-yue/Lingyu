/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This file is part of Atoll and is released under the GNU GPL v3.
 */

import AppKit
import CoreServices
import Defaults
import SwiftUI

private struct InstalledApp: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let url: URL
    let lastUsedDate: Date?

    var icon: NSImage {
        AppIconCache.shared.icon(for: url)
    }
}

private final class AppIconCache: @unchecked Sendable {
    static let shared = AppIconCache()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        // App icons can contain large representations. Keep only the icons most
        // likely to be visible instead of retaining the whole application list.
        cache.countLimit = 72
    }

    func icon(for url: URL) -> NSImage {
        let key = url.standardizedFileURL.path as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache.setObject(icon, forKey: key)
        return icon
    }
}

private actor AppCatalogCache {
    static let shared = AppCatalogCache()

    private var cachedApps: [InstalledApp]?

    func applications(loader: @Sendable () -> [InstalledApp]) -> [InstalledApp] {
        if let cachedApps {
            return cachedApps
        }
        let loaded = loader()
        cachedApps = loaded
        return loaded
    }
}

@MainActor
private final class AppFinderStore: ObservableObject {
    @Published var favorites: Set<String> {
        didSet { defaults.set(Array(favorites), forKey: favoritesKey) }
    }
    @Published var recentPaths: [String] {
        didSet { defaults.set(recentPaths, forKey: recentKey) }
    }

    private let defaults = UserDefaults.standard
    private let favoritesKey = "atoll.appFinder.favorites.v1"
    private let recentKey = "atoll.appFinder.recents.v1"

    init() {
        favorites = Set(defaults.stringArray(forKey: favoritesKey) ?? [])
        recentPaths = defaults.stringArray(forKey: recentKey) ?? []
    }

    func toggleFavorite(_ app: InstalledApp) {
        if favorites.contains(app.id) {
            favorites.remove(app.id)
        } else {
            favorites.insert(app.id)
        }
    }

    func recordLaunch(_ app: InstalledApp) {
        recentPaths.removeAll { $0 == app.id }
        recentPaths.insert(app.id, at: 0)
        recentPaths = Array(recentPaths.prefix(16))
    }
}

struct ProductivityPanelView: View {
    @ObservedObject private var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject private var timerManager = TimerManager.shared
    @AppStorage("atoll.quickAction.shortcutName") private var shortcutName = ""
    @State private var showReplaceTimerConfirmation = false
    @State private var statusMessage = "点击卡片即可执行，不再跳转到重复页面"

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 2)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.yellow)
                Text("快捷控制")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
            }

            LazyVGrid(columns: columns, spacing: 8) {
                actionCard("番茄钟 25 分钟", systemImage: "timer", status: focusTimerStatus) {
                    if timerManager.isTimerActive {
                        showReplaceTimerConfirmation = true
                    } else {
                        startFocusTimer()
                    }
                }
                actionCard("临时笔记", systemImage: "square.and.pencil", status: "新建空白笔记") {
                    Defaults[.enableNotes] = true
                    coordinator.shouldCreateNewNote = true
                    coordinator.currentView = .notes
                }
                actionCard("下载", systemImage: "arrow.down.circle", status: "在 Finder 打开") {
                    openDownloads()
                }
                actionCard("运行快捷指令", systemImage: "command", status: shortcutName.isEmpty ? "先填写名称" : shortcutName) {
                    runShortcut()
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "command")
                    .foregroundStyle(.white.opacity(0.5))
                TextField("macOS 快捷指令名称", text: $shortcutName)
                    .textFieldStyle(.plain)
                    .foregroundStyle(.white)
                if !shortcutName.isEmpty {
                    Button {
                        shortcutName = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.45))
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            Text(statusMessage)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .frame(minWidth: 680, maxWidth: 750)
        .frame(height: expandedNotchHeight, alignment: .top)
        .alert("已有计时器正在运行", isPresented: $showReplaceTimerConfirmation) {
            Button("保留当前计时器", role: .cancel) {}
            Button("重新开始 25 分钟", role: .destructive) {
                startFocusTimer()
            }
        } message: {
            Text("当前“\(timerManager.timerName)”还剩 \(formattedTimerRemaining)。重新开始会覆盖它。")
        }
    }

    private func actionCard(
        _ title: String,
        systemImage: String,
        status: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 18)
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                    Text(status)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 49)
            .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 11))
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .stroke(.white.opacity(0.05), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)，\(status)")
        .accessibilityIdentifier("Atoll.QuickAction.\(title)")
    }

    private var focusTimerStatus: String {
        timerManager.isTimerActive ? "进行中 · \(formattedTimerRemaining)" : "立即开始"
    }

    private var formattedTimerRemaining: String {
        let seconds = max(0, Int(timerManager.remainingTime.rounded(.up)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func startFocusTimer() {
        Defaults[.enableTimerFeature] = true
        timerManager.startTimer(duration: 25 * 60, name: "番茄钟 · 25 分钟")
        coordinator.noteLiveActivityInteraction(for: .timer)
        statusMessage = "已开始 25 分钟番茄钟"
    }

    private func openDownloads() {
        coordinator.preferDownloadLiveActivity()
        guard let downloadsURL = FileManager.default.urls(
            for: .downloadsDirectory,
            in: .userDomainMask
        ).first else {
            statusMessage = "未找到下载文件夹"
            return
        }
        NSWorkspace.shared.open(downloadsURL)
        statusMessage = "已打开下载文件夹"
    }

    private func runShortcut() {
        let name = shortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            statusMessage = "请先在下方填写快捷指令名称"
            return
        }

        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "run-shortcut"
        components.queryItems = [URLQueryItem(name: "name", value: name)]

        guard let url = components.url else {
            statusMessage = "快捷指令名称无法识别"
            return
        }
        NSWorkspace.shared.open(url)
        statusMessage = "已请求运行：\(name)"
    }
}

struct AppFinderPanelView: View {
    @ObservedObject private var coordinator = DynamicIslandViewCoordinator.shared
    @StateObject private var store = AppFinderStore()
    @State private var searchText = ""
    @State private var apps: [InstalledApp] = []
    @State private var selectedAppID: String?
    @State private var isLoading = true
    // Fewer, larger tiles keep the app launcher readable at a glance.
    @State private var columnCount = 6
    @FocusState private var searchFocused: Bool

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 10),
        count: 6
    )

    private var filteredApps: [InstalledApp] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var favoriteApps: [InstalledApp] {
        apps.filter { store.favorites.contains($0.id) }
    }

    private var recentApps: [InstalledApp] {
        let byID = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) })
        let launchedFromAtoll = store.recentPaths
            .compactMap { byID[$0] }
            .filter { !store.favorites.contains($0.id) }
        let launchedIDs = Set(launchedFromAtoll.map(\.id))
        let systemRecent = apps
            .filter {
                $0.lastUsedDate != nil
                    && !store.favorites.contains($0.id)
                    && !launchedIDs.contains($0.id)
            }
            .prefix(21)
        return launchedFromAtoll + systemRecent
    }

    private var otherApps: [InstalledApp] {
        let recentIDs = Set(recentApps.map(\.id))
        return apps.filter { !store.favorites.contains($0.id) && !recentIDs.contains($0.id) }
    }

    private var keyboardApps: [InstalledApp] {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return filteredApps
        }
        return favoriteApps + recentApps + otherApps
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("应用程序")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text("方向键选择 · 回车启动")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.38))
                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .foregroundStyle(.white.opacity(0.75))
                }
                .buttonStyle(.plain)
                .help("在 Finder 中打开应用程序")
            }

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.white.opacity(0.55))
                TextField("查找 App", text: $searchText)
                    .textFieldStyle(.plain)
                    .foregroundStyle(.white)
                    .focused($searchFocused)
                    .onSubmit { openSelectedApp() }
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))

            ScrollViewReader { scrollProxy in
                ScrollView(.vertical, showsIndicators: true) {
                    if isLoading {
                        VStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("正在后台扫描应用…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 100)
                    } else if filteredApps.isEmpty {
                        Text("没有找到匹配的应用")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                            .frame(maxWidth: .infinity, minHeight: 68)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                appSection("收藏", apps: favoriteApps)
                                appSection("最近使用", apps: recentApps)
                                appSection("所有应用", apps: otherApps)
                            } else {
                                appSection("搜索结果", apps: filteredApps)
                            }
                        }
                    }
                }
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { updateColumnCount(for: proxy.size.width) }
                            .onChange(of: proxy.size.width) { _, width in
                                updateColumnCount(for: width)
                            }
                    }
                }
                .onChange(of: selectedAppID) { _, appID in
                    guard let appID else { return }
                    // Keyboard navigation is a frequent action. Keep selection
                    // immediate instead of animating every arrow-key press.
                    scrollProxy.scrollTo(appID, anchor: .center)
                }
                .frame(height: max(474, appFinderNotchHeight - 106))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .frame(minWidth: appFinderNotchWidth - 80, maxWidth: appFinderNotchWidth - 40)
        .frame(height: appFinderNotchHeight, alignment: .top)
        .task {
            isLoading = true
            let loaded = await AppCatalogCache.shared.applications {
                Self.loadApplications()
            }
            apps = loaded
            selectedAppID = keyboardApps.first?.id
            isLoading = false
        }
        .onChange(of: searchText) { _, _ in
            selectedAppID = keyboardApps.first?.id
        }
        .focusable()
        .onKeyPress(.upArrow) {
            moveSelection(.up)
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveSelection(.down)
            return .handled
        }
        .onKeyPress(.leftArrow) {
            moveSelection(.left)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            moveSelection(.right)
            return .handled
        }
        .onMoveCommand(perform: moveSelection)
    }

    @ViewBuilder
    private func appSection(_ title: String, apps: [InstalledApp]) -> some View {
        if !apps.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.leading, 2)
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(apps) { app in
                        appTile(app)
                    }
                }
            }
        }
    }

    private func appTile(_ app: InstalledApp) -> some View {
        VStack(spacing: 3) {
            Image(nsImage: app.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 51, height: 51)
            Text(app.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .padding(.vertical, 10)
        .background(
            selectedAppID == app.id ? Color.accentColor.opacity(0.28) : Color.white.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(alignment: .topTrailing) {
            Button {
                store.toggleFavorite(app)
            } label: {
                Image(systemName: store.favorites.contains(app.id) ? "star.fill" : "star")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(store.favorites.contains(app.id) ? .yellow : .white.opacity(0.35))
                    .padding(6)
            }
            .buttonStyle(.plain)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(selectedAppID == app.id ? Color.accentColor.opacity(0.8) : .clear, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .id(app.id)
        .onTapGesture {
            selectedAppID = app.id
            open(app)
        }
        .help("打开 \(app.name)")
    }

    nonisolated private static func loadApplications() -> [InstalledApp] {
        let fileManager = FileManager.default
        let directories = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]
        var result: [InstalledApp] = []
        var seen = Set<String>()

        for directory in directories {
            guard let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator where url.pathExtension.lowercased() == "app" {
                let key = url.standardizedFileURL.path
                guard seen.insert(key).inserted else { continue }
                let name = Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? url.deletingPathExtension().lastPathComponent
                result.append(
                    InstalledApp(
                        id: key,
                        name: name,
                        url: url,
                        lastUsedDate: Self.lastUsedDate(for: url)
                    )
                )
            }
        }
        return result.sorted { lhs, rhs in
            switch (lhs.lastUsedDate, rhs.lastUsedDate) {
            case let (left?, right?) where left != right:
                return left > right
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }
    }

    nonisolated private static func lastUsedDate(for url: URL) -> Date? {
        guard let item = MDItemCreate(kCFAllocatorDefault, url.path as CFString),
              let value = MDItemCopyAttribute(item, kMDItemLastUsedDate) else {
            return nil
        }
        return value as? Date
    }

    private func open(_ app: InstalledApp) {
        store.recordLaunch(app)
        coordinator.restoreViewBeforeAppFinder()
        NSWorkspace.shared.open(app.url)
    }

    private func openSelectedApp() {
        guard let selected = keyboardApps.first(where: { $0.id == selectedAppID }) ?? keyboardApps.first else { return }
        open(selected)
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        let list = keyboardApps
        guard !list.isEmpty else { return }
        let current = list.firstIndex(where: { $0.id == selectedAppID }) ?? 0
        let columnStep = max(1, columnCount)
        let delta: Int
        switch direction {
        case .left: delta = -1
        case .right: delta = 1
        case .up: delta = -columnStep
        case .down: delta = columnStep
        @unknown default: delta = 0
        }
        let next = min(max(current + delta, 0), list.count - 1)
        selectedAppID = list[next].id
    }

    private func updateColumnCount(for width: CGFloat) {
        let spacing: CGFloat = 10
        let desiredColumnWidth: CGFloat = 126
        columnCount = max(1, Int((width + spacing) / (desiredColumnWidth + spacing)))
    }
}
