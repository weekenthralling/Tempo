#!/usr/bin/env bash
#
# Compiles the Foundation-only core of Tempo for macOS and runs the timing
# checks. Useful when no iOS simulator runtime is installed, and as a fast
# pre-commit sanity check.
#
# Usage: ./Scripts/verify-core.sh
#
set -euo pipefail

cd "$(dirname "$0")/.."

OUTPUT_DIR=".build/core-check"
MODULE_CACHE="$OUTPUT_DIR/module-cache"
mkdir -p "$OUTPUT_DIR" "$MODULE_CACHE"

SOURCES=(
  "Tempo/Core/TempoMath.swift"
  "Tempo/Core/TimeSignature.swift"
  "Tempo/Core/Subdivision.swift"
  "Tempo/Core/TempoMarking.swift"
  "Tempo/Core/TapTempo.swift"
  "Tempo/Core/ClickSound.swift"
  "Tempo/Core/DisplayMode.swift"
  "Tempo/Core/MetronomeSettings.swift"
  "Tempo/Core/Localization.swift"
  "Tools/CoreCheck/main.swift"
)

echo "Compiling core checks…"
swiftc -O -module-cache-path "$MODULE_CACHE" -o "$OUTPUT_DIR/tempo-core-check" "${SOURCES[@]}"

echo "Running core checks…"
"$OUTPUT_DIR/tempo-core-check"
