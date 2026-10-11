#!/bin/bash
# The speed check of milestone F12 on this computer: macos.
#
#   1. Start-up time and memory, release build (app/tool/perf_start.dart).
#   2. Frame times of scrolls and of a drag, profile build
#      (app/integration_test/perf_test.dart).
#
# The store has 1 000 tasks and a full planner week (app/tool/perf_data.dart),
# in its own folder. The data of Grove is never touched.
# Each result is one line that starts with GROVE_PERF.
# Close other heavy programs first: a busy computer gives worse numbers.
# In part 2 the window must stay in view: do not cover it and stay on its
# desktop. A part with "hidden" in its "app_states" must be taken again.
#
#   ./scripts/flutter_perf.sh macos            both parts
#   ./scripts/flutter_perf.sh macos start      part 1 only
#   ./scripts/flutter_perf.sh macos frames     part 2 only
#   GROVE_PERF_RUNS=10 ./scripts/flutter_perf.sh macos start
#   GROVE_PERF_EMPTY=1 ./scripts/flutter_perf.sh macos start
#       part 1 with the store of a new user, to see what the data adds
#
# The made-up data stays in the temporary folder of the app, in the folders
# grove-perf and grove-perf-frames. Each run makes them again.
set -euo pipefail
target="${1:-}"
part="${2:-all}"
runs="${GROVE_PERF_RUNS:-5}"
if [ "$target" != macos ]; then
  echo "usage: $0 macos [start|frames]" >&2
  exit 2
fi
cd "$(dirname "$0")/../app"
flutter pub get
out=build/perf
mkdir -p "$out"

# The time now, in microseconds since 1970.
now() { perl -MTime::HiRes=time -e 'printf("%d\n", time() * 1000000)'; }

# The memory that Activity Monitor shows for the process, from outside.
footprint_line() {
  vmmap --summary "$1" 2> /dev/null | grep -m1 'Physical footprint:' || true
}

# Builds `$1` in mode `$2` and moves the app to `$3`. The app must not stay
# in the build folder: it has the name of Grove and is not Grove.
build() {
  local mode_dir
  if [ "$2" = release ]; then mode_dir=Release; else mode_dir=Profile; fi
  flutter build macos "--$2" -t "$1"
  rm -rf "$3"
  mv "build/macos/Build/Products/$mode_dir/grove.app" "$3"
}

if [ "$part" = all ] || [ "$part" = start ]; then
  echo "== 1. start-up and memory (release build) =="
  build tool/perf_start.dart release "$out/start.app"
  bin="$out/start.app/Contents/MacOS/grove"
  GROVE_PERF=seed "$bin"
  echo "-- the first start of a day (it makes the daily backup) --"
  GROVE_PERF=start GROVE_PERF_T0="$(now)" "$bin"
  echo "-- $runs starts --"
  for _ in $(seq 1 "$runs"); do
    GROVE_PERF=start GROVE_PERF_T0="$(now)" "$bin"
  done
  echo "-- memory: after the start, and after a walk through the screens --"
  log="$out/walk.log"
  : > "$log"
  GROVE_PERF=walk GROVE_PERF_T0="$(now)" "$bin" > "$log" &
  pid=$!
  for step in start walk; do
    until grep -q "\"step\":\"$step\"" "$log"; do
      if ! kill -0 "$pid" 2> /dev/null; then
        echo "the app stopped before the step \"$step\"" >&2
        cat "$log" >&2
        exit 1
      fi
      sleep 0.2
    done
    grep "\"step\":\"$step\"" "$log"
    echo "   seen from outside, after \"$step\": $(footprint_line "$pid")"
  done
  wait "$pid"
fi

if [ "$part" = all ] || [ "$part" = frames ]; then
  echo "== 2. frame times (profile build) =="
  build integration_test/perf_test.dart profile "$out/frames.app"
  GROVE_PERF_EXIT=1 "$out/frames.app/Contents/MacOS/grove"
fi
