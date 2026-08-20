#!/usr/bin/env bash
# Starts the VM and attaches the Looking Glass viewer, in the right order.
#
# The trick: the client is launched IMMEDIATELY. While the capture host is not
# yet running, it falls back to SPICE and shows the emulated display — so boot
# and the login screen appear in the same window you will play in. No need for
# virt-manager, which removes the SPICE conflict between the two entirely.
#
# Config (override with environment variables):
#   VM        libvirt domain name          (default: win10)
#   GPU       PCI address of the guest GPU (default: auto-detected via vfio-pci)
#   SHM       shared memory device         (default: /dev/kvmfr0)
#
#   VM=my-guest ./start-vm.sh
#
# See docs/04-looking-glass.md

set -uo pipefail
VM="${VM:-${1:-win10}}"
SHM="${SHM:-/dev/kvmfr0}"
V="virsh -c qemu:///system"

ok()   { printf '  \033[32m✔\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✘\033[0m %s\n' "$*"; }
step() { printf '\n\033[1m→ %s\033[0m\n' "$*"; }

# --- locate the guest GPU --------------------------------------------------
if [ -z "${GPU:-}" ]; then
  for d in /sys/bus/pci/devices/*/; do
    [ -e "$d/class" ] || continue
    case "$(cat "$d/class")" in 0x0300*|0x0302*) ;; *) continue ;; esac
    [ "$(basename "$(readlink -f "$d/driver" 2>/dev/null)" 2>/dev/null)" = "vfio-pci" ] \
      && GPU=$(basename "$d") && break
  done
fi

step "1. Shared memory"
if [ -e "$SHM" ]; then
  ok "$SHM present"
else
  bad "$SHM missing — loading the module"
  sudo modprobe kvmfr || { bad "failed; check /etc/modules-load.d/kvmfr.conf"; exit 1; }
  ok "kvmfr loaded"
fi

step "2. Guest GPU"
if [ -z "${GPU:-}" ]; then
  bad "no GPU bound to vfio-pci"
  echo "      The card is not reserved for the VM. Check /etc/modprobe.d/vfio.conf"
  echo "      and that the initramfs was rebuilt (docs/02-host-setup.md)."
  echo "      Or set it explicitly:  GPU=0000:0a:00.0 $0"
  exit 1
fi
ok "$(lspci -nns "${GPU#0000:}" 2>/dev/null | cut -d' ' -f2- | head -c 60) → vfio-pci"

step "3. VM state"
STATE=$($V domstate "$VM" 2>/dev/null)
if [ -z "$STATE" ]; then
  bad "domain '$VM' not found — set VM=<name>"
  $V list --all 2>/dev/null | sed 's/^/      /'
  exit 1
fi
if [ "$STATE" = "running" ]; then
  ok "already running — just attaching the viewer"
else
  echo
  printf '  \033[33m⚠  The dummy plug must be UNPLUGGED to boot.\033[0m\n'
  echo '     Attached at power-on, the UEFI firmware hangs with no way back'
  echo '     except destroying the VM. See docs/04-looking-glass.md'
  echo
  read -r -p "  Plug removed? [Enter to start, Ctrl-C to abort] "
  $V start "$VM" || exit 1
  ok "VM started"
fi

step "4. Viewer"
cat <<'TXT'
  The client opens now. What to expect:
    • boot and login screen, through the SPICE fallback
    • log into Windows
    • hot-plug the dummy plug → the screen goes black
    • the capture host starts by itself and the image returns

  ⏱  Allow up to ~80 s of black screen after plugging it in. The scheduled
     task fires once a minute (Windows' minimum), so the wait depends on
     when you plug in. This is NOT a hang.

  Right Ctrl releases the keyboard.

TXT

looking-glass-client -f "$SHM" -k
RC=$?

if [ "$($V domstate "$VM" 2>/dev/null)" = "running" ]; then
  printf '\n\033[1m→ Viewer closed — the VM is still running\033[0m\n'
  echo "  Closing the window (or Ctrl-C) only stops the display."
  echo "  The VM keeps running in the background, GPU powered."
  echo
  echo "    reattach the viewer : $0"
  echo "    shut the VM down    : $(dirname "$0")/stop-vm.sh"
  echo
  read -r -p "  Shut down now? [y/N] " REP
  if [ "${REP,,}" = "y" ]; then
    exec "$(dirname "$(readlink -f "$0")")/stop-vm.sh"
  fi
  echo "  Left running."
else
  ok "VM is off"
fi
exit $RC
