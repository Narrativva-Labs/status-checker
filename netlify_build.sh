#!/usr/bin/env bash
# Netlify build: installs a pinned Flutter SDK and builds the web app.
# Required environment variables: SUPABASE_URL, SUPABASE_ANON_KEY, EMAIL_REDIRECT_URL.
set -euo pipefail

# Pinned, so a new Flutter release cannot break the deploy unexpectedly.
FLUTTER_VERSION="${FLUTTER_VERSION:-3.47.9}"

installed_version=""
if command -v flutter &> /dev/null; then
  installed_version="$(flutter --version | awk '$1 == "Flutter" {print $2}')"
fi

if [[ "$installed_version" != "$FLUTTER_VERSION" ]]; then
  echo "Installing Flutter SDK ${FLUTTER_VERSION}…"
  rm -rf flutter
  git clone --depth 1 --branch "${FLUTTER_VERSION}" https://github.com/flutter/flutter.git
  export PATH="$(pwd)/flutter/bin:$PATH"
else
  echo "Flutter already installed: $installed_version"
fi

flutter precache --web
flutter pub get

flutter build web --release \
  --dart-define=EMAIL_REDIRECT_URL="${EMAIL_REDIRECT_URL}" \
  --dart-define=SUPABASE_URL="${SUPABASE_URL}" \
  --dart-define=SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY}"

echo "Flutter web build complete at build/web"
