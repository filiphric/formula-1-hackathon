#!/usr/bin/env bash
# Build FormulaLive for a physical iPhone, install it in place, and launch it.
#   Scripts/install-iphone.sh [--device NAME] [--endpoint ws://MAC-LAN-IP:8787/live]
# Signing and endpoint details: README "Physical iPhone". Device defaults to "Ajfonis".
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

# The app ignores any other address and keeps its saved one, so refuse it here instead of reporting a good install.
if [[ -n "$endpoint" ]]; then
  scheme_and_host="$(printf '%s' "$endpoint" | tr '[:upper:]' '[:lower:]')"
  if [[ ! "$scheme_and_host" =~ ^wss?://[^/@[:space:]]+ || "$endpoint" =~ [[:space:]] ]]; then
    echo "--endpoint must be a ws:// or wss:// address such as ws://192.168.1.10:8787/live (got '$endpoint')." >&2
    exit 64
  fi
fi

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
    hardware = d.get("hardwareProperties", {})
    # Older devicectl omits "reality"; only skip a device that says it is simulated.
    if d.get("deviceProperties", {}).get("name") == name and hardware.get("reality", "physical") == "physical" and hardware.get("udid"):
        print(hardware["udid"])
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

# Arguments after `--` go to the app; without it devicectl parses -seedServerEndpoint as its own -t.
launch_args=()
[[ -n "$endpoint" ]] && launch_args=(-- -seedServerEndpoint "$endpoint")
xcrun devicectl device process launch --device "$udid" --terminate-existing "$bundle_id" ${launch_args[@]+"${launch_args[@]}"}
echo "Installed and launched $bundle_id on $device_name."
