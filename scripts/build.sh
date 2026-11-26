#!/usr/bin/env bash
# Builds Fisper.app (and the bundled whisper.cpp speech engine).
#   ./scripts/build.sh            → build/Fisper.app
#   ./scripts/build.sh --install  → also copies it to /Applications and launches it
#   ./scripts/build.sh --dmg      → also creates build/Fisper.dmg
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
WHISPER_COMMIT="${WHISPER_COMMIT:-$(cat "$ROOT/vendor/WHISPER_CPP_COMMIT" 2>/dev/null || echo master)}"
BUILD="$ROOT/build"
APP="$BUILD/Fisper.app"
mkdir -p "$BUILD"

say() { printf "\033[1;32m▸\033[0m %s\n" "$*"; }

# 1. Speech engine: whisper.cpp server, static, Metal-accelerated
if [[ ! -x vendor/whisper-server ]]; then
  say "Building whisper.cpp (${WHISPER_COMMIT:0:10}) — one time, ~2 min"
  command -v cmake >/dev/null || { echo "cmake is required: brew install cmake"; exit 1; }
  SRC="$BUILD/whisper.cpp"
  if [[ ! -d "$SRC/.git" ]]; then
    git init -q "$SRC"
    git -C "$SRC" remote add origin https://github.com/ggml-org/whisper.cpp.git
    git -C "$SRC" fetch -q --depth 1 origin "$WHISPER_COMMIT" && git -C "$SRC" checkout -q FETCH_HEAD
  fi
  cmake -S "$SRC" -B "$SRC/build" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
        -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON -DGGML_NATIVE=OFF -DGGML_CPU_ARM_ARCH=armv8.2-a+dotprod+fp16 \
        -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_EXAMPLES=ON -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 >/dev/null
  cmake --build "$SRC/build" -j "$(sysctl -n hw.ncpu)" --target whisper-server >/dev/null
  mkdir -p vendor && cp "$SRC/build/bin/whisper-server" vendor/whisper-server
fi

# 2. The app
say "Compiling Fisper (release)"
swift build -c release --arch arm64 2>&1 | grep -E "error|warning: unre|Compiling|Build" | grep -v "^$" || true
BIN="$(swift build -c release --arch arm64 --show-bin-path)/Fisper"
[[ -x "$BIN" ]] || { echo "build failed"; exit 1; }

# 3. Icon
if [[ ! -f Resources/AppIcon.icns ]]; then
  say "Rendering app icon"
  ICONSET="$BUILD/AppIcon.iconset"; rm -rf "$ICONSET"; mkdir -p "$ICONSET"
  swift scripts/make_icon.swift "$BUILD/icon-1024.png"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$BUILD/icon-1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) "$BUILD/icon-1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
fi

# 4. Bundle
say "Assembling Fisper.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Fisper"
cp vendor/whisper-server "$APP/Contents/MacOS/whisper-server"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf "APPL????" > "$APP/Contents/PkgInfo"

# 5. Sign (ad-hoc). Note: macOS ties Accessibility permission to the signature,
#    so after rebuilding you may need to toggle Fisper off/on in Privacy & Security → Accessibility.
say "Signing"
codesign --force --sign - --identifier app.fisper.whisper-server "$APP/Contents/MacOS/whisper-server"
codesign --force --sign - --identifier app.fisper.Fisper "$APP"
codesign --verify --deep "$APP"

say "Built $APP"

if [[ "${1:-}" == "--dmg" || "${2:-}" == "--dmg" ]]; then
  say "Creating DMG"
  STAGE="$BUILD/dmg"; rm -rf "$STAGE"; mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/"; ln -s /Applications "$STAGE/Applications"
  rm -f "$BUILD/Fisper.dmg"
  hdiutil create -volname Fisper -srcfolder "$STAGE" -ov -format UDZO "$BUILD/Fisper.dmg" >/dev/null
  say "Built $BUILD/Fisper.dmg"
fi

if [[ "${1:-}" == "--install" || "${2:-}" == "--install" ]]; then
  say "Installing to /Applications"
  osascript -e 'tell application id "app.fisper.Fisper" to quit' >/dev/null 2>&1 || true
  pkill -x Fisper >/dev/null 2>&1 || true
  sleep 0.5
  rm -rf /Applications/Fisper.app
  cp -R "$APP" /Applications/Fisper.app
  open /Applications/Fisper.app
  say "Fisper is running — look for the waveform in your menu bar"
fi
