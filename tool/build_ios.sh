#!/usr/bin/env bash
set -euo pipefail
flutter pub get
flutter analyze
flutter test
flutter build ios --release
