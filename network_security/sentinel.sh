#!/usr/bin/env bash
#
# sentinel.sh — Continuously monitor the network for the intruder.
# Matches by MAC first, then DHCP fingerprint, then mDNS hostname.
# Fires a desktop notification on detection.
# Usage: ./sentinel.sh [--scan-interval <seconds>]
#
# Requires: pin_intruder.sh to have been run first (builds the profile).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROFILE_DIR="$SCRIPT_DIR"
PROFILE_FILE="$PROFILE_DIR/intruder_profile.json"
ALERT_LOG="$PROFILE_DIR/alerts.log"
SENTINEL_LOG="$PROFILE_DIR/sentinel.log"
PID_FILE="$PROFILE_DIR/sentinel.pid"
SCAN_INTERVAL=30

if [ "$EUID" -ne 0 ]; then
  exec sudo env PATH="$PATH" "$0" "$@"
fi

# --stop: kill a running sentinel (must be root to kill a root process)
if [ "$1" = "--stop" ]; then
  if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if kill "$PID" 2>/dev/null; then
      echo "[*] Sentinel stopped (PID $PID)"
    else
      echo "[!] Process $PID not running (stale PID file)"
    fi
    rm -f "$PID_FILE"
  else
    echo "[!] No sentinel PID file found — is it running?"
  fi
  exit 0
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scan-interval) SCAN_INTERVAL="$2"; shift 2 ;;
    *) shift ;;
  esac
done

mkdir -p "$PROFILE_DIR"

if [ ! -f "$PROFILE_FILE" ]; then
  echo "[-] No intruder profile found at $PROFILE_FILE"
  echo "    Run ./pin_intruder.sh first to build the profile."
  exit 1
fi

# Write PID file so --stop works
echo $$ > "$PID_FILE"

# Tee all stdout/stderr to sentinel.log
exec > >(tee -a "$SENTINEL_LOG") 2>&1

IFACE=$(ip route | awk '/default/ {print $5; exit}')
GW_IP=$(ip route | awk '/default/ {print $3; exit}')
SELF_MAC=$(cat "/sys/class/net/$IFACE/address" 2>/dev/null | tr '[:upper:]' '[:lower:]')
SELF_IP=$(ip -4 addr show dev "$IFACE" | awk '/inet / {print $2}' | cut -d/ -f1)

# Load profile fields
read_profile() {
  python3 -c "
import json, sys
with open('$PROFILE_FILE') as f:
    p = json.load(f)
print(p.get('$1', ''))
" 2>/dev/null
}

KNOWN_MAC=$(read_profile mac | tr '[:upper:]' '[:lower:]')
KNOWN_DHCP_FP=$(read_profile dhcp_fingerprint)
KNOWN_DHCP_HOST=$(read_profile dhcp_hostname | tr '[:upper:]' '[:lower:]')
KNOWN_MDNS_HOST=$(read_profile mdns_hostname | tr '[:upper:]' '[:lower:]' | sed 's/\.local//')

notify() {
  local title="$1" body="$2"
  # Try notify-send (Linux desktop), fall back to Windows toast via PowerShell
  if command -v notify-send &>/dev/null; then
    DISPLAY="${DISPLAY:-:0}" notify-send --urgency=critical "$title" "$body" 2>/dev/null
  fi
  # WSL: Windows balloon notification
  powershell.exe -WindowStyle Hidden -Command "
    Add-Type -AssemblyName System.Windows.Forms
    \$n = New-Object System.Windows.Forms.NotifyIcon
    \$n.Icon = [System.Drawing.SystemIcons]::Warning
    \$n.BalloonTipTitle = '$title'
    \$n.BalloonTipText = '$body'
    \$n.Visible = \$true
    \$n.ShowBalloonTip(10000)
    Start-Sleep 3
    \$n.Dispose()
  " 2>/dev/null &
}

alert() {
  local ip="$1" mac="$2" signal="$3"
  local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
  local msg="Intruder detected via $signal — IP: $ip  MAC: $mac"
  echo "[$ts] ALERT: $msg" | tee -a "$ALERT_LOG"
  notify "Network Sentinel" "$msg"
}

log() { echo "[$(date '+%H:%M:%S')] $*"; }

echo "=========================================="
echo " Network Sentinel — $(date)"
echo " Profile: $PROFILE_FILE"
echo " Known MAC:        ${KNOWN_MAC:-(none)}"
echo " DHCP fingerprint: ${KNOWN_DHCP_FP:-(pending)}"
echo " DHCP hostname:    ${KNOWN_DHCP_HOST:-(pending)}"
echo " mDNS hostname:    ${KNOWN_MDNS_HOST:-(none)}"
echo " Scan interval:    ${SCAN_INTERVAL}s"
echo "=========================================="
echo " Ctrl+C to stop"
echo ""

# Keep track of already-alerted devices to avoid spam
ALERTED_FILE=$(mktemp)

already_alerted() { grep -qF "$1" "$ALERTED_FILE" 2>/dev/null; }
mark_alerted()    { echo "$1" >> "$ALERTED_FILE"; }
clear_alerted()   { grep -vF "$1" "$ALERTED_FILE" > "${ALERTED_FILE}.tmp" && mv "${ALERTED_FILE}.tmp" "$ALERTED_FILE"; }

# --- Background DHCP fingerprint monitor ------------------------------------
# Runs continuously, updates profile if DHCP fingerprint was pending
dhcp_monitor() {
  python3 - "$IFACE" "$KNOWN_MAC" "$KNOWN_DHCP_FP" "$KNOWN_DHCP_HOST" "$PROFILE_FILE" "$ALERT_LOG" << 'PYEOF'
import socket, struct, sys, json, time, select, subprocess
from datetime import datetime

iface, known_mac, known_fp, known_host, profile_file, alert_log = sys.argv[1:7]

def parse_dhcp(data):
    if len(data) < 240 or data[236:240] != b'\x63\x82\x53\x63':
        return None
    opts = {}
    i = 240
    while i < len(data):
        opt = data[i]
        if opt == 255: break
        if opt == 0:   i += 1; continue
        if i + 1 >= len(data): break
        ln = data[i+1]; val = data[i+2:i+2+ln]
        opts[opt] = val; i += 2 + ln
    return opts

def ip_bytes(pkt, off): return '.'.join(str(b) for b in pkt[off:off+4])
def mac_str(b): return ':'.join(f'{x:02x}' for x in b)

try:
    sock = socket.socket(socket.AF_INET, socket.SOCK_RAW, socket.IPPROTO_UDP)
    SO_BINDTODEVICE = 25
    sock.setsockopt(socket.SOL_SOCKET, SO_BINDTODEVICE, iface.encode() + b'\x00')
    sock.setblocking(False)
except Exception as e:
    print(f"[dhcp_monitor] socket error: {e}", file=sys.stderr)
    sys.exit(1)

print("[dhcp_monitor] Listening for DHCP events...", flush=True)

while True:
    ready, _, _ = select.select([sock], [], [], 5.0)
    if not ready:
        continue
    pkt = sock.recv(65535)
    ihl = (pkt[0] & 0x0F) * 4
    udp = pkt[ihl:]
    if len(udp) < 8: continue
    src_port, dst_port = struct.unpack('!HH', udp[0:4])
    if src_port != 68 or dst_port != 67: continue
    payload = udp[8:]
    opts = parse_dhcp(payload)
    if not opts: continue

    # client MAC is at bytes 28–34 of DHCP payload
    client_mac = mac_str(payload[28:34]) if len(payload) >= 34 else ''
    fp    = ','.join(str(b) for b in opts.get(55, b''))
    host  = opts.get(12, b'').decode('utf-8', errors='replace').rstrip('\x00').lower()
    vendor= opts.get(60, b'').decode('utf-8', errors='replace').rstrip('\x00')

    matched = False
    signal  = ''

    if known_mac and client_mac.lower() == known_mac.lower():
        matched = True; signal = 'DHCP+MAC'
    elif known_fp and fp == known_fp:
        matched = True; signal = 'DHCP-fingerprint'
    elif known_host and host and known_host in host:
        matched = True; signal = 'DHCP-hostname'

    if matched:
        ts = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        src_ip = ip_bytes(pkt, 12)
        msg = f"[{ts}] DHCP ALERT ({signal}): IP={src_ip} MAC={client_mac} host={host} fp={fp}"
        print(msg, flush=True)
        with open(alert_log, 'a') as f:
            f.write(msg + '\n')
        # If DHCP fp was pending, save it to profile
        if not known_fp and fp:
            try:
                with open(profile_file) as pf:
                    profile = json.load(pf)
                profile['dhcp_fingerprint']  = fp
                profile['dhcp_hostname']     = host
                profile['dhcp_vendor_class'] = vendor
                with open(profile_file, 'w') as pf:
                    json.dump(profile, pf, indent=2)
                print(f"[dhcp_monitor] Profile updated with DHCP fingerprint: {fp}", flush=True)
                known_fp   = fp
                known_host = host
            except Exception as e:
                print(f"[dhcp_monitor] Profile update failed: {e}", file=sys.stderr)
PYEOF
}

# --- Background mDNS hostname monitor ---------------------------------------
mdns_monitor() {
  [ -z "$KNOWN_MDNS_HOST" ] && return
  tcpdump -i "$IFACE" -l -n "udp port 5353" 2>/dev/null | while read -r line; do
    host=$(echo "$line" | grep -oP '[\w\-]+\.local' | head -1 | tr '[:upper:]' '[:lower:]' | sed 's/\.local//')
    [ -z "$host" ] && continue
    [ "$host" != "$KNOWN_MDNS_HOST" ] && continue
    # extract source IP
    src_ip=$(echo "$line" | awk '{print $3}' | cut -d. -f1-4)
    already_alerted "mdns:$src_ip" && continue
    alert "$src_ip" "(via mDNS)" "mDNS-hostname($host)"
    mark_alerted "mdns:$src_ip"
  done
}

# Start background monitors
dhcp_monitor &
DHCP_PID=$!
mdns_monitor &
MDNS_PID=$!
trap 'kill $DHCP_PID $MDNS_PID 2>/dev/null; rm -f "$ALERTED_FILE" "$PID_FILE"; echo ""; log "Sentinel stopped."' EXIT INT TERM

# --- Main ARP sweep loop ----------------------------------------------------
log "Sentinel active. Scanning every ${SCAN_INTERVAL}s..."

while true; do
  # Collect currently visible devices
  while IFS=$'\t' read -r ip mac vendor; do
    mac_lc="${mac,,}"
    [ "$mac_lc" = "$SELF_MAC" ] && continue
    [ "$ip" = "$SELF_IP" ]     && continue
    [ "$ip" = "$GW_IP" ]       && continue

    matched=false
    signal=""

    # 1. MAC match
    if [ -n "$KNOWN_MAC" ] && [ "$mac_lc" = "$KNOWN_MAC" ]; then
      matched=true; signal="MAC"
    fi

    if $matched; then
      if already_alerted "$ip:$mac_lc"; then
        : # already alerted for this session
      else
        alert "$ip" "$mac" "$signal"
        mark_alerted "$ip:$mac_lc"
      fi
    else
      # Device is gone/changed — clear alert so we re-alert if they return
      if already_alerted "$ip:$mac_lc"; then
        clear_alerted "$ip:$mac_lc"
      fi
    fi

  done < <(arp-scan -I "$IFACE" --localnet --ignoredups --retry=2 --timeout=1500 2>/dev/null \
             | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')

  log "Sweep done. Next in ${SCAN_INTERVAL}s. Alerts logged to $ALERT_LOG"
  sleep "$SCAN_INTERVAL"
done
