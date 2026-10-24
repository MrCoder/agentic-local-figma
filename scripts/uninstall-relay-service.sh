#!/usr/bin/env bash
# Remove the figma-edit-mcp relay launchd user agent installed by
# install-relay-service.sh: stops the service and deletes its plist.
# The log file in ~/Library/Logs is left in place.
#
# Usage: scripts/uninstall-relay-service.sh [--label L]
set -euo pipefail

LABEL="com.agentic-local-figma.relay"

die() { echo "error: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --label) [ $# -ge 2 ] || die "--label needs a value"; LABEL="$2"; shift 2 ;;
    -h|--help) sed -n '2,6p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

[ "$(uname -s)" = "Darwin" ] || die "launchd is macOS-only."

DOMAIN="gui/$(id -u)"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

if launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null; then
  echo "Stopped '$LABEL'."
else
  echo "'$LABEL' was not loaded."
fi
if [ -f "$PLIST" ]; then
  rm "$PLIST"
  echo "Removed $PLIST"
else
  echo "No plist at $PLIST"
fi
