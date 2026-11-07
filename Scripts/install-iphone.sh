#!/usr/bin/env bash
# Build FormulaLive for a physical iPhone, install it, and launch it.
#
#   Scripts/install-iphone.sh [--device NAME] [--endpoint ws://HOST:8787/live]
#
# Defaults to the device named "Ajfonis". Signing comes from Config.local.xcconfig
# (DEVELOPMENT_TEAM; see Config.local.example.xcconfig). The app is replaced in place,
# never uninstalled, so its saved settings survive.
#
# --endpoint is passed for this launch only (`-serverEndpoint`). To keep it, type it into
# the app's Connection settings once. localhost on the phone is the phone itself, so the
# endpoint must be your Mac's LAN address and the backend must listen on it (see README).
set -euo pipefail

device_name="Ajfonis"
endpoint=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --device) device_name="${2:?--device needs a name}"; shift 2 ;;
    --endpoint) endpoint="${2:?--endpoint needs a URL}"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 64 ;;
  esac
done

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
bundle_id="dev.formulalive.app"
derived="$root/.build/ios-device"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

if [[ ! -f Config.local.xcconfig ]]; then
  echo "Missing Config.local.xcconfig. Copy Config.local.example.xcconfig and set DEVELOPMENT_TEAM." >&2
  exit 1
fi

# Resolve the device's current identifier by name; it changes between pairings.
xcrun devicectl list devices --json-output "$scratch/devices.json" >/dev/null
udid="$(python3 -I - "$scratch/devices.json" "$device_name" <<'PY'
import json, sys
path, name = sys.argv[1:3]
for d in json.load(open(path))["result"]["devices"]:
    if d["deviceProperties"]["name"] == name and d["hardwareProperties"]["reality"] == "physical":
        print(d["hardwareProperties"]["udid"])
        break
PY
)"
if [[ -z "$udid" ]]; then
  echo "No physical device named '$device_name' found. Connect it, unlock it, and trust this Mac." >&2
  exit 1
fi
echo "Device: $device_name ($udid)"

xcodebuild -project FormulaLive.xcodeproj -scheme FormulaLive -configuration Debug \
  -destination "id=$udid" -derivedDataPath "$derived" -allowProvisioningUpdates build

app="$derived/Build/Products/Debug-iphoneos/FormulaLive.app"
[[ -d "$app" ]] || { echo "Build succeeded but $app is missing." >&2; exit 1; }

xcrun devicectl device install app --device "$udid" "$app"

# Arguments after `--` go to the app; without it devicectl parses -serverEndpoint as its own -t.
launch_args=()
[[ -n "$endpoint" ]] && launch_args=(-- -serverEndpoint "$endpoint")
xcrun devicectl device process launch --device "$udid" --terminate-existing "$bundle_id" ${launch_args[@]+"${launch_args[@]}"}
echo "Installed and launched $bundle_id on $device_name."
