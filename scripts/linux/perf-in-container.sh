#!/usr/bin/env bash
set -euo pipefail
cp -a /source/. /tmp/app/
cd /tmp/app
mkdir -p /output/perf-4
python3 scripts/linux/fixture_server_test.py
flutter pub get > /output/perf-4/pub-get.log 2>&1
dart format --language-version=3.4 --output=none --set-exit-if-changed integration_test
flutter analyze --no-pub > /output/perf-4/analyze.log 2>&1
python3 scripts/linux/fixture_server.py &
fixture_pid=$!
trap 'kill "$fixture_pid" 2>/dev/null || true' EXIT
python3 - <<'PY'
import time
from urllib.request import urlopen
for attempt in range(50):
    try:
        with urlopen('http://127.0.0.1:8765/perf/stats', timeout=1) as response:
            assert response.status == 200
        break
    except OSError:
        time.sleep(0.1)
else:
    raise SystemExit('fixture server did not start')
PY
# The same container preserves disk cache, each Flutter invocation starts a new app.
for phase in no-images first restart; do
    no_images=false
    if [[ "$phase" == no-images ]]; then no_images=true; fi
    xvfb-run -a -s '-screen 0 1280x900x24' \
        flutter test integration_test/linux_image_perf_test.dart -d linux --no-pub \
        --dart-define=FORUM_PERF_TRACE=true --dart-define=PERF_PHASE="$phase" \
        --dart-define=PERF_NO_IMAGES="$no_images" \
        2>&1 | tee "/output/perf-4/$phase.log"
done
