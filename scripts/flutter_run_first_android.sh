#!/bin/zsh
# Run Flutter on the first Android device ADB reports as "device" (usually USB).
# Avoids stale wireless ids like adb-1f4419ec-1xtyfu that Cursor/Flutter may still target.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}"
export ANDROID_HOME="${ANDROID_HOME:-$ANDROID_SDK_ROOT}"
export PATH="$PATH:$ANDROID_SDK_ROOT/platform-tools"

ADB="$ANDROID_SDK_ROOT/platform-tools/adb"

if [[ ! -x "$ADB" ]]; then
  echo "adb not found at $ADB — set ANDROID_SDK_ROOT or install platform-tools."
  exit 1
fi

pkill -9 adb 2>/dev/null || true
sleep 1
"$ADB" start-server
# Drop stale TCP/wireless connections so Flutter does not keep a dead serial.
"$ADB" disconnect 2>/dev/null || true

# Collect non-emulator devices in "device" state (tab-separated: SERIAL\tSTATE).
# Wireless ADB serials look like adb-HASH._adb-tls-connect._tcp — Flutter may show
# only the short prefix (adb-HASH); that is NOT valid for adb/flutter -d.
declare -a usb_ids=()
declare -a wireless_ids=()
while IFS=$'\t' read -r sid state _; do
  [[ "$sid" == "List"* ]] && continue
  [[ -z "${sid// }" ]] && continue
  [[ "$state" != "device" ]] && continue
  [[ "$sid" == emulator-* ]] && continue
  if [[ "$sid" == adb-*"_adb-tls-connect._tcp" ]]; then
    wireless_ids+=("$sid")
  else
    usb_ids+=("$sid")
  fi
done < <("$ADB" devices)

serial=""
if (( ${#usb_ids[@]} > 0 )); then
  serial="${usb_ids[1]}"
elif (( ${#wireless_ids[@]} > 0 )); then
  # Prefer primary pairing over duplicate " (2)." mDNS entries when both appear.
  for w in "${wireless_ids[@]}"; do
    if [[ "$w" != *" (2)."* ]]; then
      serial="$w"
      break
    fi
  done
  [[ -z "$serial" ]] && serial="${wireless_ids[1]}"
fi

if [[ -z "$serial" ]]; then
  echo "No Android USB/device ready. Plug in the phone, enable USB debugging, accept the RSA prompt."
  echo ""
  "$ADB" devices -l
  exit 1
fi

echo "Using Android device: $serial"
exec flutter run -d "$serial" "$@"
