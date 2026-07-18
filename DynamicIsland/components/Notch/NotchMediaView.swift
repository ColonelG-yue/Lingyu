/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This file is part of Atoll and is released under the GNU GPL v3.
 */

import Defaults
import AppKit
import SwiftUI

struct NotchMediaView: View {
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @ObservedObject private var musicManager = MusicManager.shared
    @Default(.mediaController) private var mediaController
    let albumArtNamespace: Namespace.ID

    var body: some View {
        Group {
            if musicManager.hasActiveSession {
                activeMediaView
            } else {
                emptyMediaView
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, minHeight: expandedNotchHeight, alignment: .top)
    }

    private var activeMediaView: some View {
        GeometryReader { geometry in
            let artworkSize = min(172, max(126, min(geometry.size.height - 24, geometry.size.width * 0.25)))

            HStack(alignment: .center, spacing: 22) {
                AlbumArtView(vm: vm, albumArtNamespace: albumArtNamespace)
                    .frame(width: artworkSize, height: artworkSize)
                    .clipped()

                MusicControlsView()
                    .frame(maxWidth: .infinity, minHeight: artworkSize, alignment: .center)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.055), lineWidth: 1)
            }
        }
    }

    private var emptyMediaView: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
            Text("暂无正在播放的媒体")
                .font(.headline)
                .foregroundStyle(.white)
            Text("开始播放音乐或视频后，封面、进度和控制按钮会显示在这里。")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.48))
            Button("打开\(mediaController.localizedName)") {
                openPreferredMediaApp()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func openPreferredMediaApp() {
        let preferredBundleID: String = {
            if let activeBundleID = musicManager.bundleIdentifier, !activeBundleID.isEmpty {
                return activeBundleID
            }
            switch mediaController {
            case .nowPlaying, .appleMusic:
                return "com.apple.Music"
            case .spotify:
                return SpotifyController.bundleIdentifier
            case .youtubeMusic:
                return YouTubeMusicConfiguration.default.bundleIdentifier
            case .amazonMusic:
                return AmazonMusicController.bundleIdentifier
            case .cider:
                return CiderController.bundleIdentifier
            }
        }()

        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: preferredBundleID) else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Music.app"))
            return
        }
        NSWorkspace.shared.open(appURL)
    }
}
