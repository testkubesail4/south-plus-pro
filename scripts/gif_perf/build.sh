#!/usr/bin/env bash
set -euo pipefail

revision=${1:?Usage: build.sh REVISION OUTPUT.apk [android-x64|android-arm64] [boundary]}
output=$(realpath -m "${2:?Supply an output APK path}")
platform=${3:-android-x64}
source=$(git rev-parse --show-toplevel)
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT

git -C "$source" archive "$revision" | tar -x -C "$scratch"
cd "$scratch"
mkdir -p scripts/gif_perf
cp "$source/scripts/gif_perf/main.dart" scripts/gif_perf/
sed -i 's/applicationId = "com.example.south_plus_rewrite"/applicationId = "com.example.south_plus_gif_bench14"/' android/app/build.gradle.kts
sed -i '/android:label=/a\        android:usesCleartextTraffic="true"' android/app/src/main/AndroidManifest.xml

if [[ ${4:-} == boundary ]]; then
    python3 - <<'PY'
from pathlib import Path

path = Path('lib/features/thread/thread_rich_content.dart')
source = path.read_text()
header, component = source.split('class ThreadInlineImage extends', 1)
opening = '            child: ClipRRect(\n'
closing = '            ),\n          ),\n        );'
if component.count(opening) != 1 or closing not in component:
    raise SystemExit('ThreadInlineImage structure changed')
component = component.replace(opening, '            child: RepaintBoundary(child: ClipRRect(\n', 1)
component = component.replace(closing, '            )),\n          ),\n        );', 1)
path.write_text(header + 'class ThreadInlineImage extends' + component)
PY
fi
flutter pub get --enforce-lockfile
flutter build apk --profile --target-platform "$platform" --no-pub --target scripts/gif_perf/main.dart
cp build/app/outputs/flutter-apk/app-profile.apk "$output"
