#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
# With full Xcode selected, swift test finds the Testing framework itself.
# Forcing the Command Line Tools copy then breaks the Testing macros.
if [[ "$(xcode-select -p)" == *Xcode*.app* ]]; then
  exec swift test "$@"
fi
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
L=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
swift test -Xswiftc -F -Xswiftc $F -Xlinker -F -Xlinker $F \
  -Xlinker -rpath -Xlinker $F -Xlinker -rpath -Xlinker $L "$@"
