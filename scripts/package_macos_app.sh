#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="VideoFlow"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
BUNDLED_APP_DIR="$RESOURCES_DIR/app"

if [ ! -x "$ROOT_DIR/.venv/bin/python" ]; then
  echo "Missing .venv. Run dependency installation before packaging." >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>VideoFlow</string>
  <key>CFBundleDisplayName</key>
  <string>VideoFlow</string>
  <key>CFBundleIdentifier</key>
  <string>com.ashlesh-v.videoflow</string>
  <key>CFBundleVersion</key>
  <string>1.0.0</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>CFBundleExecutable</key>
  <string>VideoFlow</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>11.0</string>
</dict>
</plist>
PLIST

rsync -a \
  --exclude '.git/' \
  --exclude '.DS_Store' \
  --exclude '/dist/' \
  --exclude '/storage/' \
  --exclude '/logs/' \
  --exclude '/models/' \
  --exclude '__pycache__/' \
  --exclude '*.pyc' \
  --exclude 'config.toml' \
  "$ROOT_DIR/" "$BUNDLED_APP_DIR/"

cp "$BUNDLED_APP_DIR/config.example.toml" "$BUNDLED_APP_DIR/config.toml"

cat > "$MACOS_DIR/$APP_NAME" <<'LAUNCHER'
#!/usr/bin/env bash
set -euo pipefail

APP_ROOT="$(cd "$(dirname "$0")/../Resources/app" && pwd)"
PYTHON="$APP_ROOT/.venv/bin/python"
LOG_DIR="$APP_ROOT/logs"
HOME_DIR="$APP_ROOT/.home"
mkdir -p "$LOG_DIR" "$HOME_DIR"

if [ ! -x "$PYTHON" ]; then
  osascript -e 'display dialog "VideoFlow could not find its bundled Python environment." buttons {"OK"} default button "OK" with icon stop'
  exit 1
fi

PORT="$("$PYTHON" - <<'PY'
import socket
for port in range(8501, 8600):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        try:
            sock.bind(("127.0.0.1", port))
        except OSError:
            continue
        print(port)
        raise SystemExit
raise SystemExit(1)
PY
)"

URL="http://127.0.0.1:$PORT"
export HOME="$HOME_DIR"
export PYTHONPATH="$APP_ROOT${PYTHONPATH:+:$PYTHONPATH}"

cd "$APP_ROOT"
open "$URL"
exec "$PYTHON" -m streamlit run "$APP_ROOT/webui/Main.py" \
  --server.address=127.0.0.1 \
  --server.port="$PORT" \
  --browser.serverAddress=127.0.0.1 \
  --browser.gatherUsageStats=false \
  --server.headless=true \
  --server.showEmailPrompt=false \
  --server.enableCORS=true \
  >> "$LOG_DIR/videoflow.log" 2>&1
LAUNCHER

chmod +x "$MACOS_DIR/$APP_NAME"

echo "Created $APP_DIR"
echo "Double-click it, or run: open \"$APP_DIR\""
