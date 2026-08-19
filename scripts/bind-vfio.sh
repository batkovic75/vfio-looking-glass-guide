#!/usr/bin/env bash
# Generates /etc/modprobe.d/vfio.conf for the GPU you want to pass to a VM.
#
# Prints the config; it does NOT write it. Review, then copy it yourself.
#
# See docs/02-host-setup.md

set -uo pipefail

ok()   { printf '  \033[32m✔\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✘\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
hdr()  { printf '\n\033[1m== %s\033[0m\n' "$*"; }

hdr "Graphics cards found"
mapfile -t GPUS < <(lspci -Dnn | grep -E '\[030[02]\]')
if [ "${#GPUS[@]}" -lt 2 ]; then
  bad "Fewer than two GPUs. Passthrough needs one for the host and one for the VM."
  printf '  %s\n' "${GPUS[@]}"
  exit 1
fi
i=0
for g in "${GPUS[@]}"; do
  addr=$(echo "$g" | cut -d' ' -f1)
  drv=$(basename "$(readlink -f "/sys/bus/pci/devices/$addr/driver" 2>/dev/null)" 2>/dev/null || echo none)
  printf '  [%d] %s\n      driver: %s\n' "$i" "$g" "$drv"
  i=$((i+1))
done

TARGET="${1:-}"
if [ -z "$TARGET" ]; then
  echo
  echo "Usage: $0 <pci-address>      e.g. $0 0000:84:00.0"
  echo "       Pick the card for the VM — NOT the one driving your desktop."
  exit 0
fi

SYS="/sys/bus/pci/devices/$TARGET"
[ -d "$SYS" ] || { bad "Unknown device: $TARGET"; exit 1; }

hdr "Safety checks"

# Refuse the card currently driving a connected display.
CONNECTED=0
for card in /sys/class/drm/card*/; do
  [ -e "$card/device" ] || continue
  if [ "$(basename "$(readlink -f "$card/device")")" = "$TARGET" ]; then
    for st in "$card"*/status; do
      [ -r "$st" ] && [ "$(cat "$st")" = "connected" ] && CONNECTED=1
    done
  fi
done
if [ "$CONNECTED" = "1" ]; then
  bad "$TARGET currently drives a CONNECTED display."
  echo "      Binding it to vfio-pci will leave you without a desktop."
  echo "      Continue only if you are certain (e.g. you have a second output)."
  exit 1
fi
ok "not driving a connected display"

# IOMMU group cleanliness
GRP=""
for g in /sys/kernel/iommu_groups/*/devices/"$TARGET"; do
  [ -e "$g" ] && GRP=$(basename "$(dirname "$(dirname "$g")")")
done
[ -n "$GRP" ] || { bad "No IOMMU group — is IOMMU enabled?"; exit 1; }
DIRTY=$(for d in /sys/kernel/iommu_groups/"$GRP"/devices/*; do
          lspci -nns "$(basename "$d")"
        done | grep -icE 'USB|SATA|Ethernet|Network|Non-Volatile memory|SMBus' || true)
if [ "$DIRTY" -gt 0 ]; then
  bad "IOMMU group $GRP also holds $DIRTY critical non-GPU device(s):"
  for d in /sys/kernel/iommu_groups/"$GRP"/devices/*; do
    lspci -nns "$(basename "$d")" | sed 's/^/        /'
  done
  exit 1
fi
ok "IOMMU group $GRP is clean"

hdr "Device IDs to bind"
SLOT="${TARGET%.*}"
IDS=""
for d in /sys/bus/pci/devices/"${SLOT}".*; do
  [ -d "$d" ] || continue
  a=$(basename "$d")
  id=$(lspci -nms "${a#0000:}" | awk '{gsub(/"/,"");print $3":"$4}')
  lspci -nns "${a#0000:}" | sed 's/^/  /'
  IDS="${IDS:+$IDS,}$id"
done

# Refuse if a host GPU shares the same vendor:device ID.
for g in "${GPUS[@]}"; do
  addr=$(echo "$g" | cut -d' ' -f1)
  [ "$addr" = "$TARGET" ] && continue
  hid=$(lspci -nms "${addr#0000:}" | awk '{gsub(/"/,"");print $3":"$4}')
  case ",$IDS," in
    *",$hid,"*)
      bad "Your other GPU ($addr) shares the ID $hid."
      echo "      Binding by ID would capture BOTH cards. Bind by PCI address"
      echo "      instead — see the Arch Wiki, 'identical guest and host GPUs'."
      exit 1 ;;
  esac
done
ok "no conflict with the host GPU"

hdr "Config to write to /etc/modprobe.d/vfio.conf"
cat <<EOF

options vfio-pci ids=$IDS
softdep nvidia pre: vfio-pci
softdep nouveau pre: vfio-pci
softdep amdgpu pre: vfio-pci
softdep radeon pre: vfio-pci

EOF
warn "Keep only the softdep lines matching your guest GPU's vendor."
echo
echo "Then add vfio to the initramfs and reboot:"
echo "  /etc/mkinitcpio.conf →  MODULES=(vfio_pci vfio vfio_iommu_type1)"
echo "  sudo mkinitcpio -P && sudo reboot"
echo
echo "Verify afterwards:  lspci -nnk -s ${SLOT#0000:}"
echo "  both functions must show 'Kernel driver in use: vfio-pci'"
