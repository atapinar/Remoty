#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@17}"
TOOLS="$HOME/Library/Caches/remoty-tools"
R8="$TOOLS/r8.jar"
if [ ! -f "$R8" ]; then
  mkdir -p "$TOOLS"
  curl -fsSLo "$R8" https://dl.google.com/dl/android/maven2/com/android/tools/r8/8.5.35/r8-8.5.35.jar
fi
WORK="$(mktemp -d /tmp/remoty-pq.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
"$JAVA_HOME/bin/javac" --release 8 -d "$WORK/classes" pq/PQ.java
"$JAVA_HOME/bin/java" -cp "$R8" com.android.tools.r8.D8 --release --min-api 26 --output "$WORK" "$WORK/classes/PQ.class"
mkdir -p Sources/AndroidTVMenubar/Helpers
cp "$WORK/classes.dex" Sources/AndroidTVMenubar/Helpers/pq.dex
printf 'Built %s\n' Sources/AndroidTVMenubar/Helpers/pq.dex
