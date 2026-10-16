#!/bin/zsh
# 构建 uuchat.app(arm64 + x86_64 通用二进制, ad-hoc 签名)并打包 zip / dmg
#   用法: scripts/build.sh [版本号]      默认取 git tag 或 dev
set -euo pipefail
cd "${0:A:h}/.."

VERSION="${1:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}"
VERSION="${VERSION:-dev}"
APP="build/uuchat.app"
MIN_OS="13.0"

rm -rf build/uuchat-* "$APP" && mkdir -p build dist

echo "==> 编译 (v$VERSION)"
for arch in arm64 x86_64; do
  swiftc -O -target "$arch-apple-macos$MIN_OS" -I include Sources/*.swift -o "build/uuchat-$arch"
done
lipo -create build/uuchat-arm64 build/uuchat-x86_64 -output build/uuchat

echo "==> 组装 App"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/uuchat "$APP/Contents/MacOS/uuchat"
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP"

echo "==> 打包"
ZIP="dist/uuchat-$VERSION.zip"
DMG="dist/uuchat-$VERSION.dmg"
rm -f "$ZIP" "$DMG"
ditto -c -k --keepParent "$APP" "$ZIP"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/" && ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "uuchat $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

echo "完成:"
ls -lh "$ZIP" "$DMG"
lipo -info "$APP/Contents/MacOS/uuchat"
