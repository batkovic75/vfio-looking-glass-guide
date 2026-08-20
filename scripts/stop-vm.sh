#!/usr/bin/env bash
# Shuts the VM down cleanly and closes the Looking Glass viewer.
#
# Prefers ACPI shutdown, which asks Windows to power off normally. A hard
# destroy is only offered as a last resort: repeated hard resets are what feed
# the PCIe reset bug (docs/07-troubleshooting.md#gpu-vanished-from-the-guest).
#
# Config (override with environment variables):
#   VM        libvirt domain name  (default: win10)
#   TIMEOUT   seconds before offering a hard cut (default: 120)
#
# See docs/04-looking-glass.md

set -uo pipefail
VM="${VM:-${1:-win10}}"
TIMEOUT="${TIMEOUT:-120}"
V="virsh -c qemu:///system"

ok()   { printf '  \033[32m✔\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✘\033[0m %s\n' "$*"; }
step() { printf '\n\033[1m→ %s\033[0m\n' "$*"; }

step "1. VM state"
STATE=$($V domstate "$VM" 2>/dev/null)
case "$STATE" in
  "shut off") ok "already off" ;;
  running)    ok "running" ;;
  "")         bad "domain '$VM' not found — set VM=<name>"
              $V list --all 2>/dev/null | sed 's/^/      /'; exit 1 ;;
  *)          bad "unexpected state: $STATE" ;;
esac

if [ "$STATE" = "running" ]; then
  step "2. ACPI shutdown"
  echo "  Windows receives a power-off request and shuts down normally."
  $V shutdown "$VM" >/dev/null 2>&1 || { bad "command refused"; exit 1; }

  elapsed=0
  while [ "$elapsed" -lt "$TIMEOUT" ]; do
    sleep 5; elapsed=$((elapsed+5))
    [ "$($V domstate "$VM" 2>/dev/null)" = "shut off" ] && break
    printf '\r  shutting down… %ss' "$elapsed"
  done
  printf '\r\033[K'

  if [ "$($V domstate "$VM" 2>/dev/null)" = "shut off" ]; then
    ok "clean shutdown in ${elapsed}s"
  else
    bad "still running after ${TIMEOUT}s"
    cat <<'TXT'

  Two usual causes:
    • an application is blocking shutdown behind a confirmation dialog
      → reopen Looking Glass and dismiss it
    • the VM is stuck on the UEFI splash (dummy plug attached at boot)
      → a hard cut is safe here: Windows never started, so there is
        nothing to corrupt

TXT
    read -r -p "  Force it off? [y/N] " REP
    if [ "${REP,,}" = "y" ]; then
      $V destroy "$VM" >/dev/null 2>&1 && ok "VM forced off"
      echo "      ⚠ repeated hard cuts feed the PCIe reset bug"
    else
      echo "      left as is — run this script again later"
      exit 0
    fi
  fi
fi

step "3. Viewer"
if pgrep -x looking-glass-client >/dev/null 2>&1; then
  pkill -x looking-glass-client 2>/dev/null && ok "Looking Glass client closed"
else
  ok "no client open"
fi

step "4. Do this now"
printf '  \033[33m⚠  Unplug the dummy plug.\033[0m\n'
cat <<'TXT'
     Otherwise the next boot hangs on the UEFI splash and you will have to
     destroy the VM to get out. Easier to do it while you are thinking of it.
TXT
echo
echo "  Start again:  $(dirname "$0")/start-vm.sh"
