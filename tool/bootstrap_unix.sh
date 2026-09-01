#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

if [[ "$(uname -s)" == "Darwin" ]]; then
  PLATFORMS="android,ios,web"
else
  PLATFORMS="android,web"
fi

flutter create --project-name wmn_standalone --platforms="$PLATFORMS" .

WASM_PATH="web/sqlite3.wasm"
if [[ ! -f "$WASM_PATH" ]]; then
  curl -L \
    "https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-3.5.2/sqlite3.wasm" \
    -o "$WASM_PATH"
fi

flutter pub get
dart run tool/verify_clean_platform.dart
flutter analyze
flutter test
flutter doctor
