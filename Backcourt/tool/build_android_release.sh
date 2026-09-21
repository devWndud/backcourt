#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
KEYCHAIN_SERVICE="kr.backcourt.backcourt.upload-keystore"
KEYCHAIN_ACCOUNT="backcourt"

BACKCOURT_RELEASE_PASSWORD="$(
  security find-generic-password \
    -a "$KEYCHAIN_ACCOUNT" \
    -s "$KEYCHAIN_SERVICE" \
    -w
)"

export BACKCOURT_KEYSTORE_PASSWORD="$BACKCOURT_RELEASE_PASSWORD"
export BACKCOURT_KEY_PASSWORD="$BACKCOURT_RELEASE_PASSWORD"

cd "$APP_DIR"
flutter build appbundle --release

unset BACKCOURT_RELEASE_PASSWORD
unset BACKCOURT_KEYSTORE_PASSWORD
unset BACKCOURT_KEY_PASSWORD

echo "AAB: $APP_DIR/build/app/outputs/bundle/release/app-release.aab"
