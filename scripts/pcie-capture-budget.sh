#!/usr/bin/env bash
# Works out which resolution/refresh combinations your PCIe link can sustain
# for Looking Glass capture.
#
# Looking Glass reads every frame back from the guest GPU uncompressed:
#     bytes/second = width * height * 4 * refresh_hz
# If that exceeds the link, VSync drops the rate to an exact divisor — which is
# why a 120 Hz display can yield a suspiciously round 60.
#
# See docs/05-display-tuning.md#capture-bandwidth

set -uo pipefail

ok()   { printf '  \033[32m✔\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✘\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
hdr()  { printf '\n\033[1m== %s\033[0m\n' "$*"; }

# --- pick the device -------------------------------------------------------
DEV="${1:-}"
if [ -z "$DEV" ]; then
  # default: a GPU currently bound to vfio-pci, i.e. the one passed to a VM
  for d in /sys/bus/pci/devices/*/; do
    [ -e "$d/class" ] || continue
    case "$(cat "$d/class")" in 0x0300*|0x0302*) ;; *) continue ;; esac
    drv=$(basename "$(readlink -f "$d/driver" 2>/dev/null)" 2>/dev/null || echo none)
    [ "$drv" = "vfio-pci" ] && DEV=$(basename "$d") && break
  done
fi

if [ -z "$DEV" ]; then
  bad "No GPU bound to vfio-pci found."
  echo "      Pass an address explicitly:  $0 0000:84:00.0"
  echo "      Available GPUs:"
  lspci -Dnn | grep -E '\[030[02]\]' | sed 's/^/        /'
  exit 1
fi

SYS="/sys/bus/pci/devices/$DEV"
[ -d "$SYS" ] || { bad "Unknown device: $DEV"; exit 1; }

hdr "1. Device"
lspci -nns "${DEV#0000:}" 2>/dev/null | sed 's/^/  /'

hdr "2. PCIe link"
SPEED=$(cat "$SYS/current_link_speed" 2>/dev/null || echo "?")
WIDTH=$(cat "$SYS/current_link_width" 2>/dev/null || echo "?")
MAXW=$(cat "$SYS/max_link_width" 2>/dev/null || echo "?")
printf '  negotiated : %s, x%s\n' "$SPEED" "$WIDTH"
printf '  device max : x%s\n' "$MAXW"

# the upstream bridge tells you whether a narrow link is the slot's fault
UP=$(basename "$(dirname "$(readlink -f "$SYS")")" 2>/dev/null)
if [ -r "/sys/bus/pci/devices/$UP/max_link_width" ]; then
  UPMAX=$(cat "/sys/bus/pci/devices/$UP/max_link_width")
  printf '  root port  : %s, max x%s\n' "$UP" "$UPMAX"
  if [ "$UPMAX" = "$WIDTH" ] && [ "$WIDTH" != "$MAXW" ]; then
    warn "The slot itself is wired x$WIDTH — reseating the card will not help."
  fi
fi

[ "$WIDTH" = "?" ] && { bad "Cannot read link width."; exit 1; }
if [ "$WIDTH" != "$MAXW" ] && [ "${UPMAX:-}" != "$WIDTH" ]; then
  warn "Running below the card's capability — check seating and BIOS."
fi

# --- per-lane throughput ---------------------------------------------------
GTS=$(echo "$SPEED" | grep -oE '^[0-9.]+')
case "$GTS" in
  2.5) LANE=250   ; GEN=1 ;;   # 8b/10b
  5|5.0) LANE=500 ; GEN=2 ;;   # 8b/10b
  8|8.0) LANE=985 ; GEN=3 ;;   # 128b/130b
  16|16.0) LANE=1969 ; GEN=4 ;;
  32|32.0) LANE=3938 ; GEN=5 ;;
  64|64.0) LANE=7877 ; GEN=6 ;;
  *) bad "Unrecognised link speed: $SPEED"; exit 1 ;;
esac

RAW=$(awk -v l="$LANE" -v w="$WIDTH" 'BEGIN{printf "%.2f", l*w/1000}')
# ~80% is what large DMA readback realistically achieves after overhead
USABLE=$(awk -v r="$RAW" 'BEGIN{printf "%.2f", r*0.8}')

printf '\n  PCIe %s.0 x%s → %s GB/s theoretical, \033[1m%s GB/s realistic\033[0m\n' \
  "$GEN" "$WIDTH" "$RAW" "$USABLE"

hdr "3. Capture budget"
echo "  bytes/s = width × height × 4 × refresh"
echo
printf '  %-18s %10s %12s   %s\n' "MODE" "PER FRAME" "BANDWIDTH" "VERDICT"
printf '  %s\n' "--------------------------------------------------------------"

for mode in \
  "1600x900:60" "1600x900:120" \
  "1920x1080:60" "1920x1080:75" "1920x1080:90" "1920x1080:120" "1920x1080:144" \
  "2560x1080:60" "2560x1080:90" "2560x1080:120" \
  "2560x1440:60" "2560x1440:75" "2560x1440:90" "2560x1440:100" "2560x1440:120" \
  "3440x1440:60" "3440x1440:75" "3440x1440:90" \
  "3840x2160:30" "3840x2160:60" "3840x2160:90"
do
  res="${mode%%:*}"; hz="${mode##*:}"
  w="${res%%x*}"; h="${res##*x}"
  read -r frame bw verdict <<<"$(awk -v w="$w" -v h="$h" -v hz="$hz" -v u="$USABLE" 'BEGIN{
      f = w*h*4/1048576;
      b = w*h*4*hz/1000000000;
      if (b <= u*0.85)      v="OK";
      else if (b <= u)      v="TIGHT";
      else                  v="NO";
      printf "%.2f %.2f %s", f, b, v
  }')"
  case "$verdict" in
    OK)    col="\033[32m✔ fits\033[0m" ;;
    TIGHT) col="\033[33m~ marginal\033[0m" ;;
    NO)    col="\033[31m✘ exceeds link\033[0m" ;;
  esac
  printf '  %-18s %7s MB %8s GB/s   ' "${res} @ ${hz}Hz" "$frame" "$bw"
  printf "$col\n"
done

hdr "4. How to read this"
cat <<'EOF'
  ✔ fits          headroom for the capture path
  ~ marginal      may work; expect VSync to halve the rate under load
  ✘ exceeds link  will not sustain — VSync drops to an exact divisor

  Pick the highest mode marked "fits", then create exactly that mode in the
  guest with CRU and delete other entries at the same resolution, so the
  application cannot pick a slower one.

  Intermediate refresh rates are legitimate: if 120 does not fit and 60 wastes
  headroom, create 75, 90 or 100.

  Full reasoning: docs/05-display-tuning.md#capture-bandwidth
EOF
