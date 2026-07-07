#!/bin/sh
# Runs the test suite. The Swift Testing framework ships with the Command Line
# Tools but its framework/dylib paths aren't wired into `swift test` there, so
# we point the compiler, linker, and runtime loader at them explicitly. With a
# full Xcode selected (`xcode-select`), a plain `swift test` also works.
set -e

FW="$(xcode-select -p)/Library/Developer/Frameworks"
LIB="$(xcode-select -p)/Library/Developer/usr/lib"

exec swift test \
  -Xswiftc -F -Xswiftc "$FW" \
  -Xlinker -F -Xlinker "$FW" \
  -Xlinker -rpath -Xlinker "$FW" \
  -Xlinker -rpath -Xlinker "$LIB" \
  "$@"
