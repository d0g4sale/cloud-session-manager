#!/bin/sh
# Runs the test suite. The Swift Testing framework ships with the Command Line
# Tools but its framework/dylib paths aren't wired into `swift test` there, so
# we point the compiler, linker, and runtime loader at them explicitly. A full
# Xcode (as on CI) keeps them on the default search paths — and the CLT paths
# below don't exist there — so only add the flags when they're actually present;
# otherwise a plain `swift test` works.
set -e

FW="$(xcode-select -p)/Library/Developer/Frameworks"
LIB="$(xcode-select -p)/Library/Developer/usr/lib"

if [ -d "$FW" ]; then
  exec swift test \
    -Xswiftc -F -Xswiftc "$FW" \
    -Xlinker -F -Xlinker "$FW" \
    -Xlinker -rpath -Xlinker "$FW" \
    -Xlinker -rpath -Xlinker "$LIB" \
    "$@"
else
  exec swift test "$@"
fi
