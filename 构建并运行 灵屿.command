#!/bin/zsh

set -euo pipefail

ROOT_DIR="${0:A:h}"
DERIVED_DIR="$ROOT_DIR/.build/DerivedData"
BUILT_APP="$DERIVED_DIR/Build/Products/Debug/Lingyu.app"
INSTALL_DIR="$HOME/Applications"
# Keep the already-authorized development bundle path stable. Finder and
# System Settings use CFBundleDisplayName ("灵屿 Lingyu"), while preserving
# this path avoids creating another duplicate app/TCC permission entry.
INSTALLED_APP="$INSTALL_DIR/Atoll Dev.app"

echo "正在编译灵屿 Lingyu…"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild \
  -quiet \
  -project "$ROOT_DIR/DynamicIsland.xcodeproj" \
  -scheme DynamicIsland \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "正在安装到 $INSTALLED_APP…"
mkdir -p "$INSTALL_DIR"
pkill -f "$INSTALLED_APP/Contents/MacOS/Lingyu" 2>/dev/null || true
pkill -f "$INSTALLED_APP/Contents/MacOS/Atoll" 2>/dev/null || true
# `ditto` merges bundles and leaves renamed executables behind. A mirrored
# install removes stale files, otherwise macOS can relaunch the old Atoll
# binary even though Info.plist already points at Lingyu.
/usr/bin/rsync -a --delete "$BUILT_APP/" "$INSTALLED_APP/"

echo "正在启动灵屿 Lingyu Dev…"
open "$INSTALLED_APP"
echo "完成。以后可直接打开灵屿 Lingyu Dev；本脚本不注册全局快捷键。"
