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
PYTHON_CMD=("$PYTHON")
LOG_DIR="$APP_ROOT/logs"
HOME_DIR="$APP_ROOT/.home"
mkdir -p "$LOG_DIR" "$HOME_DIR"
LAUNCHER_LOG="$LOG_DIR/launcher.log"
touch "$LAUNCHER_LOG"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting VideoFlow launcher" >> "$LAUNCHER_LOG"
echo "APP_ROOT=$APP_ROOT" >> "$LAUNCHER_LOG"

if [ ! -x "$PYTHON" ]; then
  echo "Bundled Python missing: $PYTHON" >> "$LAUNCHER_LOG"
  osascript -e 'display dialog "VideoFlow could not find its bundled Python environment." buttons {"OK"} default button "OK" with icon stop'
  exit 1
fi

if [ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" = "1" ] && command -v arch >/dev/null 2>&1; then
  PYTHON_CMD=(arch -arm64 "$PYTHON")
fi
echo "Python command: ${PYTHON_CMD[*]}" >> "$LAUNCHER_LOG"

PORT="$("${PYTHON_CMD[@]}" - <<'PY'
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
export NO_PROXY="127.0.0.1,localhost${NO_PROXY:+,$NO_PROXY}"
export no_proxy="127.0.0.1,localhost${no_proxy:+,$no_proxy}"

cd "$APP_ROOT"
echo "Selected URL: $URL" >> "$LAUNCHER_LOG"
"${PYTHON_CMD[@]}" -m streamlit run "$APP_ROOT/webui/Main.py" \
  --server.address=127.0.0.1 \
  --server.port="$PORT" \
  --browser.serverAddress=127.0.0.1 \
  --browser.gatherUsageStats=false \
  --server.headless=true \
  --server.showEmailPrompt=false \
  --server.enableCORS=true \
  >> "$LOG_DIR/videoflow.log" 2>&1 &

SERVER_PID=$!
export SERVER_PID
echo "Streamlit PID: $SERVER_PID" >> "$LAUNCHER_LOG"
trap 'kill "$SERVER_PID" 2>/dev/null || true' INT TERM EXIT

if "${PYTHON_CMD[@]}" - "$URL" <<'PY'
import os
import sys
import time
import urllib.request

url = sys.argv[1]
for _ in range(180):
    try:
        os.kill(int(os.environ["SERVER_PID"]), 0)
    except Exception:
        raise SystemExit(2)
    try:
        with urllib.request.urlopen(url, timeout=0.5) as response:
            if response.status < 500:
                raise SystemExit(0)
    except Exception:
        time.sleep(0.5)
raise SystemExit(1)
PY
then
  echo "Server responded, opening $URL" >> "$LAUNCHER_LOG"
  open "$URL"
else
  status=$?
  echo "Server did not respond, health-check status $status" >> "$LAUNCHER_LOG"
  osascript -e 'display dialog "VideoFlow started but the local web page did not respond. Check logs/videoflow.log inside the app package." buttons {"OK"} default button "OK" with icon caution'
fi

wait "$SERVER_PID"
LAUNCHER

chmod +x "$MACOS_DIR/$APP_NAME"

echo "Created $APP_DIR"
echo "Double-click it, or run: open \"$APP_DIR\""
