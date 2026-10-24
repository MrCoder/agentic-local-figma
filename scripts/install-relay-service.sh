#!/bin/bash
# Install the figma-edit-mcp WebSocket relay as a macOS launchd user agent:
# starts at login, restarts on exit, logs to ~/Library/Logs/<label>.log.
#
# Usage: scripts/install-relay-service.sh [--label L] [--port N] [--socket PATH] [--force]
#   --label   launchd label            (default: com.agentic-local-figma.relay)
#   --port    relay port               (default: 3055)
#   --socket  path to dist/socket.js   (default: dist/socket.js next to this repo)
#   --force   install even if another process already listens on the port
#             (the new service will then fail to bind until that process exits)
set -euo pipefail

LABEL="com.agentic-local-figma.relay"
PORT=3055
FORCE=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SOCKET="$SCRIPT_DIR/../dist/socket.js"

die() { echo "error: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --label)  [ $# -ge 2 ] || die "--label needs a value"; LABEL="$2"; shift 2 ;;
    --port)   [ $# -ge 2 ] || die "--port needs a value"; PORT="$2"; shift 2 ;;
    --socket) [ $# -ge 2 ] || die "--socket needs a value"; SOCKET="$2"; shift 2 ;;
    --force)  FORCE=1; shift ;;
    -h|--help) sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

[ "$(uname -s)" = "Darwin" ] || die "launchd is macOS-only. On Linux use a systemd --user unit (see README)."
case "$PORT" in ''|*[!0-9]*) die "--port must be a number, got '$PORT'" ;; esac

# Absolute path to dist/socket.js.
[ -f "$SOCKET" ] || die "relay entry not found: $SOCKET (run 'bun run build', or pass --socket <path>)"
SOCKET="$(cd "$(dirname "$SOCKET")" && pwd -P)/$(basename "$SOCKET")"

# Absolute path to node. launchd has no shell profile, so shims that rely on
# PATH setup (Volta) must be resolved to the real binary now.
NODE="$(command -v node)" || die "node not found on PATH"
case "$NODE" in
  *.volta*)
    if command -v volta >/dev/null 2>&1; then
      NODE="$(volta which node)" || die "volta could not resolve node"
    fi
    ;;
esac
[ -x "$NODE" ] || die "node is not executable: $NODE"

UID_NUM="$(id -u)"
DOMAIN="gui/$UID_NUM"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/$LABEL.log"

# Refuse when something other than this service already owns the port.
listener_pids() { lsof -nP -iTCP:"$PORT" -sTCP:LISTEN -t 2>/dev/null || true; }
service_pid() {
  launchctl print "$DOMAIN/$LABEL" 2>/dev/null | awk '/^[[:space:]]*pid = /{print $3; exit}'
}
OWN_PID="$(service_pid || true)"
for pid in $(listener_pids); do
  if [ -n "$OWN_PID" ] && [ "$pid" = "$OWN_PID" ]; then continue; fi
  if [ "$FORCE" -eq 0 ]; then
    echo "error: port $PORT is already in use by a process not managed by '$LABEL':" >&2
    lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >&2 || true
    echo "Stop it first, pick another --port, or pass --force." >&2
    exit 1
  fi
  echo "warning: port $PORT is held by PID $pid; --force given, installing anyway." >&2
done

mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$NODE</string>
    <string>$SOCKET</string>
    <string>--port</string>
    <string>$PORT</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
PLIST_EOF
plutil -lint "$PLIST" >/dev/null || die "generated plist is invalid: $PLIST"

# Replace any existing instance with this label, then load the new plist.
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
if ! launchctl bootstrap "$DOMAIN" "$PLIST"; then
  rm -f "$PLIST"
  die "could not load relay service '$LABEL'"
fi

cleanup_failed_install() {
  launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
  rm -f "$PLIST"
}

for _ in $(seq 1 20); do
  PID="$(service_pid || true)"
  if [ -n "$PID" ] && listener_pids | grep -qx "$PID" &&
     curl -s --connect-timeout 1 --max-time 1 -o /dev/null "http://localhost:$PORT"; then
    echo "Relay '$LABEL' is running."
    echo "  port:   $PORT  (ws://localhost:$PORT)"
    echo "  pid:    $PID"
    echo "  node:   $NODE"
    echo "  socket: $SOCKET"
    echo "  plist:  $PLIST"
    echo "  log:    $LOG"
    echo "  restart: launchctl kickstart -k $DOMAIN/$LABEL"
    exit 0
  fi
  sleep 0.5
done

echo "error: relay did not answer on http://localhost:$PORT after 20 checks. Check the log:" >&2
tail -n 20 "$LOG" >&2 || true
cleanup_failed_install
exit 1
