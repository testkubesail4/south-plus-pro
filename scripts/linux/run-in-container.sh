#!/usr/bin/env bash
set -euo pipefail
cp -a /source/. /tmp/app/
cd /tmp/app
python3 scripts/linux/fixture_server_test.py
flutter pub get > /output/pub-get.log 2>&1
dart format --language-version=3.4 --output=none --set-exit-if-changed integration_test
flutter analyze --no-pub > /output/analyze.log 2>&1
python3 scripts/linux/fixture_server.py &
fixture_pid=$!
trap 'kill "$fixture_pid" 2>/dev/null || true' EXIT
# Readiness avoids racing the first app request against server startup.
python3 - <<'PY'
import time
from urllib.request import urlopen
for attempt in range(50):
    try:
        with urlopen('http://127.0.0.1:8765/index.php', timeout=1) as response:
            assert response.status == 200
        break
    except OSError:
        time.sleep(0.1)
else:
    raise SystemExit('fixture server did not start')
PY
xvfb-run -a -s '-screen 0 1280x900x24' \
    flutter test integration_test/linux_smoke_test.dart -d linux --no-pub \
    2>&1 | tee /output/smoke.log
