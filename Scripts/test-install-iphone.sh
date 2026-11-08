#!/usr/bin/env bash
# Checks that install-iphone.sh rejects an unusable --endpoint before it builds or touches a device.
set -u
script="$(cd "$(dirname "$0")" && pwd)/install-iphone.sh"
failures=0
for bad in "192.168.1.102:8789/live" "http://192.168.1.102:8789/live" "ws://" "ws://host name/live" "not a url"; do
  "$script" --endpoint "$bad" >/dev/null 2>&1
  status=$?
  if [[ $status -ne 64 ]]; then
    echo "FAIL: --endpoint '$bad' exited $status, expected 64" >&2
    failures=$((failures + 1))
  fi
done
# A valid address gets past validation; it then stops at the missing-config or missing-device check.
out="$("$script" --endpoint "WS://192.168.1.102:8789/live" --device "No Such Phone" 2>&1)"
if [[ "$out" == *"--endpoint must be"* ]]; then
  echo "FAIL: a valid ws:// address was rejected" >&2
  failures=$((failures + 1))
fi
[[ $failures -eq 0 ]] && echo "install-iphone.sh endpoint checks passed"
exit $failures
