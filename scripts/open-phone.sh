#!/system/bin/sh
set -eu
BASE=/data/local/dsh-verify-20261117-a1
"$BASE/scripts/service.sh" status >/dev/null || { echo 'Harness is not running. Run: bash phone.sh start' >&2; exit 1; }
URL=$(sed -n 's/^dsh web: \(http:\/\/127\.0\.0\.1:3080\/?token=[A-Za-z0-9_-][A-Za-z0-9_-]*\).*$/\1/p' "$BASE/logs/web.log" | tail -n 1)
test -n "$URL" || { echo 'No authenticated launch URL was found.' >&2; exit 1; }
if ! am start -W -a android.intent.action.VIEW -p com.android.chrome -d "$URL" >/dev/null 2>&1; then
  echo 'Could not open Chrome. Ensure Chrome is installed and the phone is unlocked.' >&2
  exit 1
fi
sleep 2
# Direct navigation handles the Strict-cookie redirect observed on the test phone.
if input keycombination 113 40 && input text http://127.0.0.1:3080/ && input keyevent 66; then
  echo 'Opened Harness in Chrome.'
else
  echo 'In Chrome, enter http://127.0.0.1:3080/ directly in the address bar.' >&2
  exit 1
fi
