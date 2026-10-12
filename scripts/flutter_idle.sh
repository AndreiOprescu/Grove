#!/bin/bash
# The idle check on macOS: what Grove costs while its window is open and
# nobody touches it. It builds app/tool/idle_check.dart in profile mode,
# starts it once for each case, and reads the processor time of the process
# with `ps` at second 5 and at second 25. The answer is the share of one
# core in those 20 seconds.
#
#   ./scripts/flutter_idle.sh                 build, then measure
#   ./scripts/flutter_idle.sh path/to/X.app   measure an app that is built
#
# The app uses its own data folder in the temporary folder. It never touches
# the data of Grove.
#
# The app is started from the shell, not with `open`: its window opens but
# does not take the keyboard from the person at the Mac. The check app
# always behaves as in front (all its clocks run), whatever the system
# tells it. The line of each 5 seconds says how many frames were really
# drawn: a case with far fewer frames than the others was slowed down by
# the system (a covered window, App Nap after about 30 seconds) and does
# not count. That is why the reading ends at second 25.
set -euo pipefail
cd "$(dirname "$0")/../app"
app="${1:-}"
if [ -z "$app" ]; then
  flutter pub get
  flutter build macos --profile -t tool/idle_check.dart
  app="$(ls -d build/macos/Build/Products/Profile/*.app | head -1)"
fi
bin="$(ls "$app"/Contents/MacOS/* | head -1)"
log="$(mktemp -t grove-idle)"

# The processor time of a process so far, in hundredths of a second.
cpu() {
  ps -o time= -p "$1" 2>/dev/null | awk '{
    n = split($1, p, ":"); s = 0
    for (i = 1; i <= n; i++) s = s * 60 + p[i]
    printf "%d", s * 100
  }'
}

one() {
  local name="$1"; shift
  env "$@" GROVE_IDLE_SECONDS=30 "$bin" > "$log" 2>&1 &
  local pid=$!
  sleep 5
  local a; a="$(cpu "$pid" || true)"
  sleep 20
  local b; b="$(cpu "$pid" || true)"
  wait "$pid" || true
  if [ -z "$a" ] || [ -z "$b" ]; then
    echo "== $name: no reading, the app did not run for 25 seconds"
    cat "$log"
    return 0
  fi
  echo "== $name: $(( (b - a) * 100 / 2000 )) % of one core (processor time $(( b - a )) hundredths of a second in 20 s)"
  grep GROVE_IDLE "$log" || true
}

one "garden, Motion on" GROVE_IDLE_SCREEN=garden
one "notes, Motion on" GROVE_IDLE_SCREEN=notes
one "planner, Motion on" GROVE_IDLE_SCREEN=planner
one "today, Motion on" GROVE_IDLE_SCREEN=today
one "planner, Motion off" GROVE_IDLE_SCREEN=planner GROVE_IDLE_MOTION=off
rm -f "$log"
