#!/bin/bash

# 1. 建立 .app 目錄結構
APP_NAME="MeetingTranslator"
APP_DIR="${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MAC_OS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "🧹 清理舊的編譯檔案..."
rm -rf "$APP_DIR"

echo "📂 建立 App 目錄結構..."
mkdir -p "$MAC_OS_DIR"
mkdir -p "$RESOURCES_DIR"

# 2. 獲取當前 SDK 路徑
SDK_PATH=$(xcrun --show-sdk-path --sdk macosx 2>/dev/null)

if [ -z "$SDK_PATH" ]; then
  echo "⚠️ 找不到 SDK，嘗試使用預設路徑..."
  SDK_PATH="/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
fi

echo "SDK 路徑: $SDK_PATH"

ARCH=$(uname -m)
echo "🛠 開始編譯 Swift 檔案 (target: ${ARCH}-apple-macos13.0)..."
swiftc \
  -sdk "$SDK_PATH" \
  -target "${ARCH}-apple-macos13.0" \
  -O \
  -o "${MAC_OS_DIR}/${APP_NAME}" \
  TranslatorApp.swift \
  ContentView.swift \
  AudioCaptureManager.swift \
  AudioPlaybackManager.swift \
  GeminiLiveConnection.swift \
  FloatingSubtitleWindow.swift

if [ $? -ne 0 ]; then
  echo "❌ 編譯失敗！"
  exit 1
fi

# 3. 複製 App Icon
if [ -f "AppIcon.icns" ]; then
  echo "🎨 複製 App Icon..."
  cp "AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi

# 4. 建立 Info.plist
echo "📝 產生 Info.plist..."
cat <<EOF > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.poc.MeetingTranslator</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>MeetingTranslator 需要螢幕錄製權限，以便擷取會議應用程式的音訊進行即時翻譯。</string>
</dict>
</plist>
EOF

# 5. Ad-hoc 簽名（ScreenCaptureKit 需要簽名才能出現在系統隱私設定清單中）
echo "🔏 進行 ad-hoc 簽名..."
codesign --sign - --force --deep --preserve-metadata=entitlements "${APP_DIR}"

if [ $? -ne 0 ]; then
  echo "⚠️  簽名失敗，App 可能無法取得螢幕錄製權限"
else
  echo "✅ 簽名完成"
fi

echo "✅ 打包完成！"

# 每次重新簽名後 TCC 身分會改變，自動重置讓系統重新觸發授權彈窗
echo "🔄 重置螢幕錄製權限（ad-hoc 簽名每次都會更換身分）..."
tccutil reset ScreenCapture com.poc.MeetingTranslator 2>/dev/null && echo "   ✅ 已重置，開啟 App 後系統會重新詢問授權" || true

echo ""
echo "👉 執行以下指令開啟 App（首次開啟後點『↻』會跳出螢幕錄製授權對話框）:"
echo "   open ${APP_DIR}"
