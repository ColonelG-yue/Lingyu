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

import AppKit
import Defaults
import SwiftUI
import UserNotifications

private enum CodexTaskState: Sendable {
    case running
    case completed
    case recent
}

private struct CodexSessionSummary: Identifiable, Sendable {
    let id: String
    let title: String
    let modifiedAt: Date
    let state: CodexTaskState
}

struct NotchLLMUsageView: View {
    @ObservedObject private var manager = LLMUsageManager.shared
    @Default(.enableLLMUsageFeature) private var enableLLMUsageFeature
    @Default(.enableCodexProvider) private var enableCodexProvider
    @State private var recentSessions: [CodexSessionSummary] = []
    @State private var isLoadingSessions = true
    @AppStorage("codexSubscriptionRenewalDay") private var renewalDay = 30
    @AppStorage("codexSubscriptionReminderLeadDays") private var reminderLeadDays = 7
    @AppStorage("codexSubscriptionPaidCycle") private var paidCycle = ""
    @AppStorage("codexSubscriptionSystemNotifications") private var systemNotificationsEnabled = false

    private var latestSession: CodexSessionSummary? { recentSessions.first }
    private var todaySessionCount: Int {
        recentSessions.filter { Calendar.current.isDateInToday($0.modifiedAt) }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Codex", systemImage: "sparkles")
                    .font(.headline)
                Text("本地任务中心")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                TimelineView(.periodic(from: .now, by: 10)) { context in
                    codexSessionBadge(now: context.date)
                }
                Button {
                    refreshDashboard(forceUsage: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("刷新 Codex 状态")
            }

            if enableCodexProvider {
                VStack(spacing: 8) {
                    subscriptionReminderCard

                    HStack(alignment: .top, spacing: 10) {
                        VStack(spacing: 8) {
                            currentTaskCard
                            usageSummaryCard
                        }
                        .frame(width: 280)

                        recentTasksCard
                    }
                }
            } else {
                VStack(spacing: 9) {
                    Image(systemName: "terminal")
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                    Text("Codex 监控尚未启用")
                        .font(.headline)
                    Text("启用后会读取本机 ~/.codex/sessions，显示最近会话、Token 用量和额度。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("启用 Codex") {
                        enableLLMUsageFeature = true
                        enableCodexProvider = true
                        Defaults[.enableClaudeProvider] = false
                        Defaults[.enableCursorProvider] = false
                        manager.refreshAll(force: true)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .onAppear {
            enableLLMUsageFeature = true
            enableCodexProvider = true
            Defaults[.enableClaudeProvider] = false
            Defaults[.enableCursorProvider] = false
            refreshDashboard(forceUsage: false)
            scheduleSubscriptionNotificationsIfNeeded()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { break }
                let sessions = await Task.detached(priority: .utility) {
                    Self.loadRecentCodexSessions()
                }.value
                recentSessions = sessions
                isLoadingSessions = false
            }
        }
    }

    private var currentTaskCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("当前状态", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("今日 \(todaySessionCount) 个会话")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let latestSession {
                Text(latestSession.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.94))
                    .lineLimit(2)
                HStack {
                    Text(sessionState(for: latestSession))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(sessionTint(for: latestSession))
                    Text(latestSession.modifiedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("打开 Codex") { openCodex() }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                }
            } else if isLoadingSessions {
                ProgressView().controlSize(.small)
            } else {
                Text("尚未发现本地 Codex 任务")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
    }

    private var usageSummaryCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label("Token 与额度", systemImage: "gauge.with.dots.needle.50percent")
                    .font(.caption.weight(.semibold))
                Spacer()
            }
            usageContent(for: .codex)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
    }

    private var subscriptionReminderCard: some View {
        let renewal = upcomingRenewalDate()
        let cycle = cycleKey(for: renewal)
        let isPaid = paidCycle == cycle
        let days = max(0, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: renewal)).day ?? 0)
        let isReminderWindow = days <= reminderLeadDays

        return HStack(spacing: 10) {
            Image(systemName: isPaid ? "checkmark.seal.fill" : "creditcard.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isPaid ? .green : (isReminderWindow ? .orange : .white.opacity(0.9)))

            VStack(alignment: .leading, spacing: 2) {
                Text(isPaid ? "Codex 本周期已充值" : (isReminderWindow ? "Codex 还有 \(days) 天续费" : "Codex 下次续费：\(formattedDate(renewal, includeYear: false))"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isPaid ? .green : (isReminderWindow ? .orange : .white.opacity(0.92)))
                Text(isPaid
                     ? "下次从 \(formattedDate(Calendar.current.date(byAdding: .day, value: -reminderLeadDays, to: followingRenewalDate(after: renewal)) ?? renewal, includeYear: false)) 开始提醒"
                     : "每月 \(renewalDay) 日续费，提前 \(reminderLeadDays) 天提醒")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button {
                toggleSystemNotifications()
            } label: {
                Image(systemName: systemNotificationsEnabled ? "bell.fill" : "bell.slash")
                    .font(.caption)
                    .foregroundStyle(systemNotificationsEnabled ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
            .help(systemNotificationsEnabled ? "关闭系统续费通知" : "开启系统续费通知")

            Button(isPaid ? "撤销标记" : "本月已充值") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    paidCycle = isPaid ? "" : cycle
                }
                scheduleSubscriptionNotificationsIfNeeded()
            }
            .buttonStyle(.borderedProminent)
            .tint(isPaid ? .gray.opacity(0.45) : (isReminderWindow ? .orange : .blue))
            .controlSize(.mini)
        }
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
    }

    private func upcomingRenewalDate(from now: Date = Date()) -> Date {
        let calendar = Calendar.current
        let currentComponents = calendar.dateComponents([.year, .month], from: now)
        let currentRenewal = renewalDate(year: currentComponents.year!, month: currentComponents.month!)
        let endOfRenewalDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: currentRenewal) ?? currentRenewal
        if now <= endOfRenewalDay { return currentRenewal }
        return followingRenewalDate(after: currentRenewal)
    }

    private func followingRenewalDate(after date: Date) -> Date {
        let calendar = Calendar.current
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: date) ?? date
        let components = calendar.dateComponents([.year, .month], from: nextMonth)
        return renewalDate(year: components.year!, month: components.month!)
    }

    private func renewalDate(year: Int, month: Int) -> Date {
        let calendar = Calendar.current
        let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
        let daysInMonth = calendar.range(of: .day, in: .month, for: first)?.count ?? 28
        return calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: min(max(1, renewalDay), daysInMonth),
            hour: 10
        )) ?? first
    }

    private func cycleKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }

    private func formattedDate(_ date: Date, includeYear: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = includeYear ? "yyyy年M月d日" : "M月d日"
        return formatter.string(from: date)
    }

    private func toggleSystemNotifications() {
        let center = UNUserNotificationCenter.current()
        if systemNotificationsEnabled {
            systemNotificationsEnabled = false
            center.removePendingNotificationRequests(withIdentifiers: subscriptionNotificationIDs)
            return
        }

        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async {
                systemNotificationsEnabled = granted
                if granted {
                    scheduleSubscriptionNotificationsIfNeeded()
                }
            }
        }
    }

    private var subscriptionNotificationIDs: [String] {
        ["codex-subscription-reminder-start", "codex-subscription-reminder-due"]
    }

    private func scheduleSubscriptionNotificationsIfNeeded() {
        guard systemNotificationsEnabled else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: subscriptionNotificationIDs)

        var renewal = upcomingRenewalDate()
        if paidCycle == cycleKey(for: renewal) {
            renewal = followingRenewalDate(after: renewal)
        }
        let calendar = Calendar.current
        let reminderStart = calendar.date(byAdding: .day, value: -reminderLeadDays, to: renewal) ?? renewal

        scheduleSubscriptionNotification(
            identifier: subscriptionNotificationIDs[0],
            date: reminderStart,
            title: "Codex 即将续费",
            body: "距离本月 Codex 续费日还有 \(reminderLeadDays) 天。充值后可在 Atoll 中标记完成。"
        )
        scheduleSubscriptionNotification(
            identifier: subscriptionNotificationIDs[1],
            date: renewal,
            title: "Codex 今日续费",
            body: "请确认本月 Codex 是否已经充值。"
        )
    }

    private func scheduleSubscriptionNotification(identifier: String, date: Date, title: String, body: String) {
        guard date > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    private var recentTasksCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("最近任务", systemImage: "clock.arrow.circlepath")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("读取自 ~/.codex/sessions")
                    .font(.caption2)
                    .foregroundStyle(.secondary.opacity(0.75))
            }

            if isLoadingSessions {
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if recentSessions.isEmpty {
                Text("完成一次 Codex 任务后会显示在这里。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                VStack(spacing: 5) {
                    ForEach(recentSessions.prefix(4)) { session in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(sessionTint(for: session))
                                .frame(width: 7, height: 7)
                            Text(session.title)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white.opacity(0.9))
                                .lineLimit(1)
                            Spacer()
                            Text(session.modifiedAt, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 9)
                        .frame(height: 35)
                        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
                    }
                }
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, minHeight: 205, alignment: .topLeading)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
    }

    @ViewBuilder
    private func codexSessionBadge(now: Date) -> some View {
        if let session = latestSession {
            let modified = session.modifiedAt
            HStack(spacing: 5) {
                Circle()
                    .fill(sessionTint(for: session))
                    .frame(width: 7, height: 7)
                Text(sessionBadgeLabel(for: session, now: now))
                    .font(.caption2.weight(.semibold))
                Text(modified, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.white.opacity(0.07), in: Capsule())
        } else {
            Text("未发现本地会话")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func refreshDashboard(forceUsage: Bool) {
        manager.refreshAll(force: forceUsage)
        isLoadingSessions = true
        Task {
            let sessions = await Task.detached(priority: .userInitiated) {
                Self.loadRecentCodexSessions()
            }.value
            recentSessions = sessions
            isLoadingSessions = false
        }
    }

    nonisolated private static func loadRecentCodexSessions() -> [CodexSessionSummary] {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [(URL, Date)] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { continue }
            files.append((url, date))
        }
        return files
            .sorted { $0.1 > $1.1 }
            .prefix(12)
            .map { url, date in
                CodexSessionSummary(
                    id: url.path,
                    title: codexTaskTitle(from: url),
                    modifiedAt: date,
                    state: codexTaskState(from: url, modifiedAt: date)
                )
            }
    }

    nonisolated private static func codexTaskTitle(from url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return "Codex 会话"
        }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 384 * 1024), !data.isEmpty else {
            return "Codex 会话"
        }
        for line in data.split(separator: 0x0A) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  object["type"] as? String == "event_msg",
                  let payload = object["payload"] as? [String: Any],
                  payload["type"] as? String == "user_message",
                  let rawMessage = payload["message"] as? String else { continue }
            let title = cleanedTaskTitle(rawMessage)
            if !title.isEmpty { return title }
        }
        return url.deletingPathExtension().lastPathComponent
    }

    nonisolated private static func cleanedTaskTitle(_ raw: String) -> String {
        var candidate = raw
        if let marker = candidate.range(of: "# My request for Codex:") {
            candidate = String(candidate[marker.upperBound...])
        }
        let ignoredPrefixes = [
            "# AGENTS.md instructions",
            "<environment_context>",
            "# Files mentioned",
            "# Response annotations:",
            "The following is the Codex agent history"
        ]
        let lines = candidate
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                !line.isEmpty
                    && !ignoredPrefixes.contains(where: { line.hasPrefix($0) })
                    && !line.hasPrefix("<image")
                    && !line.hasPrefix("![")
            }
        guard let first = lines.first else { return "" }
        return first.count > 72 ? String(first.prefix(72)) + "…" : first
    }

    nonisolated private static func codexTaskState(from url: URL, modifiedAt: Date) -> CodexTaskState {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .recent }
        defer { try? handle.close() }

        let tailByteCount: UInt64 = 512 * 1024
        let fileSize = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: fileSize > tailByteCount ? fileSize - tailByteCount : 0)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return .recent }

        var lastStarted = -1
        var lastCompleted = -1
        for (index, line) in data.split(separator: 0x0A).enumerated() {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  object["type"] as? String == "event_msg",
                  let payload = object["payload"] as? [String: Any],
                  let eventType = payload["type"] as? String else { continue }
            if eventType == "task_started" {
                lastStarted = index
            } else if eventType == "task_complete" {
                lastCompleted = index
            }
        }

        if lastStarted > lastCompleted { return .running }
        if lastCompleted >= 0 { return .completed }
        return Date().timeIntervalSince(modifiedAt) < 120 ? .running : .recent
    }

    private func sessionState(for session: CodexSessionSummary) -> String {
        switch session.state {
        case .running:
            return "正在执行"
        case .completed:
            return "已完成"
        case .recent:
            let age = Date().timeIntervalSince(session.modifiedAt)
            return age < 1800 ? "最近活动" : "已暂停"
        }
    }

    private func sessionBadgeLabel(for session: CodexSessionSummary, now: Date) -> String {
        switch session.state {
        case .running: return "任务执行中"
        case .completed: return "最近已完成"
        case .recent: return now.timeIntervalSince(session.modifiedAt) < 1800 ? "最近使用" : "暂无活动"
        }
    }

    private func sessionTint(for session: CodexSessionSummary) -> Color {
        switch session.state {
        case .running: return .green
        case .completed: return .blue
        case .recent:
            return Date().timeIntervalSince(session.modifiedAt) < 1800 ? .orange : .secondary
        }
    }

    private func openCodex() {
        let candidates = [
            URL(fileURLWithPath: "/Applications/ChatGPT.app"),
            URL(fileURLWithPath: "/Applications/ChatGPT Classic.app")
        ]
        if let appURL = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            NSWorkspace.shared.open(appURL)
        }
    }

    @ViewBuilder
    private func card(for provider: ProviderID) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(provider.displayName).font(.headline)
            switch manager.results[provider] ?? .loading {
            case .loading:
                ProgressView().controlSize(.small)
            case .failure(let reason):
                Text(reason).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            case .success(let snap):
                success(snap)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func usageContent(for provider: ProviderID) -> some View {
        switch manager.results[provider] ?? .loading {
        case .loading:
            ProgressView().controlSize(.small)
        case .failure(let reason):
            Text(reason)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        case .success(let snapshot):
            success(snapshot)
        }
    }

    @ViewBuilder
    private func success(_ snap: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if snap.sessionLimit == nil && snap.weekLimit == nil {
                window("今日", snap.today, prominent: true)
                window("本周", snap.week)
                window("本次", snap.session)
                Text("暂未读取到额度信息").font(.caption2).foregroundStyle(.secondary.opacity(0.7))
            } else {
                if let limit = snap.sessionLimit { quotaGauge("本次", limit) }
                if let limit = snap.weekLimit { quotaGauge("本周", limit) }
                VStack(alignment: .leading, spacing: 2) {
                    window("今日", snap.today, compact: true)
                    window("本周", snap.week, compact: true)
                }
            }
        }
    }

    @ViewBuilder
    private func quotaGauge(_ label: String, _ limit: UsageLimit) -> some View {
        let usedPct = Int(limit.used.rounded())
        let leftPct = max(0, 100 - usedPct)
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if let resets = resetsIn(limit.resetsAt) {
                    Text(resets).font(.caption2).foregroundStyle(.secondary)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.15))
                    Capsule().fill(gaugeTint(limit.fraction)).frame(width: max(4, geo.size.width * limit.fraction))
                }
            }
            .frame(height: 6)
            HStack {
                Text("已用 \(usedPct)%").font(.caption2).monospacedDigit()
                Spacer()
                Text("剩余 \(leftPct)%").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }

    private func gaugeTint(_ fraction: Double) -> Color {
        if fraction > 0.95 { return .red }
        if fraction > 0.9 { return .orange }
        return .accentColor
    }

    private func resetsIn(_ date: Date?) -> String? {
        guard let date else { return nil }
        let seconds = Int(date.timeIntervalSinceNow)
        guard seconds > 0 else { return nil }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return hours > 0 ? "\(hours)小时\(minutes)分后重置" : "\(minutes)分后重置"
    }

    private func window(_ label: String, _ totals: UsageTotals, prominent: Bool = false, compact: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label).font(.caption2).foregroundStyle(.secondary).frame(width: compact ? 34 : 48, alignment: .leading)
            Text(tokens(totals.totalTokens))
                .font(.system(size: compact ? 11 : (prominent ? 17 : 13), weight: prominent ? .bold : .semibold, design: .rounded))
                .monospacedDigit()
            Spacer(minLength: 4)
            Text(totals.hasUnpricedModel ? money(totals.costUSD) + "+" : money(totals.costUSD))
                .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private func tokens(_ n: Int) -> String {
        switch n {
        case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000)
        case 1_000...: return String(format: "%.1fk", Double(n) / 1_000)
        default: return "\(n)"
        }
    }

    // Locale-aware formatting pinned to USD — amounts come from the USD pricing table, so the currency code stays fixed.
    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f
    }()

    private func money(_ v: Double) -> String {
        Self.currencyFormatter.string(from: v as NSNumber) ?? String(format: "$%.2f", v)
    }
}
