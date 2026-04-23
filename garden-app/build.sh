#!/bin/bash
set -euo pipefail

FLUTTER_VERSION="3.29.0"
FLUTTER_DIR="$HOME/flutter"
FLUTTER_BIN="$FLUTTER_DIR/bin/flutter"
FLUTTER_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"

echo "▶ Flutter build — GARDEN web"
echo "  version : $FLUTTER_VERSION"
echo "  API_URL : ${API_URL:-NOT SET}"

# ── 1. Install Flutter if not cached ────────────────────────────────────────
if [ ! -f "$FLUTTER_BIN" ]; then
  echo "▶ Downloading Flutter $FLUTTER_VERSION..."
  curl -fsSL "$FLUTTER_URL" -o /tmp/flutter.tar.xz
  mkdir -p "$HOME"
  tar xf /tmp/flutter.tar.xz -C "$HOME"
  rm /tmp/flutter.tar.xz
  echo "✓ Flutter extracted to $FLUTTER_DIR"
else
  echo "✓ Flutter already cached at $FLUTTER_DIR"
fi

export PATH="$FLUTTER_BIN/../:$PATH"
export PATH="$FLUTTER_DIR/bin/cache/dart-sdk/bin:$PATH"

# ── 2. Verify ────────────────────────────────────────────────────────────────
flutter --version

# ── 3. Configure ─────────────────────────────────────────────────────────────
flutter config --enable-web --no-analytics
flutter pub get

# ── 4. Build ─────────────────────────────────────────────────────────────────
flutter build web \
  --release \
  --dart-define=API_URL="${API_URL:-https://garden-api-1ldd.onrender.com/api}" \
  --web-renderer canvaskit \
  --pwa-strategy offline-first

echo "✓ Built → build/web ($(du -sh build/web | cut -f1))"
