#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
L=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
swift test -Xswiftc -F -Xswiftc $F -Xlinker -F -Xlinker $F \
  -Xlinker -rpath -Xlinker $F -Xlinker -rpath -Xlinker $L "$@"
