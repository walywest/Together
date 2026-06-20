#!/usr/bin/env bash
#
# pin_intruder.sh — Build a device fingerprint profile of the intruder.
# Run during the isolation window (family devices off) to capture identity
# signals that persist across MAC address changes.
# Usage: ./pin_intruder.sh [suspect-ip] [known-mac]

if [ "$EUID" -ne 0 ]; then
  exec sudo env PATH="$PATH" "$0" "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IFACE=$(ip route | awk '/default/ {print $5; exit}')
PROFILE_DIR="$SCRIPT_DIR"
PROFILE_FILE="$PROFILE_DIR/intruder_profile.json"
mkdir -p "$PROFILE_DIR"

log() { echo "[$(date '+%H:%M:%S')] $*"; }
sep() { echo "--------------------------------------------------"; }

echo "======================================================"
echo " Intruder Pinning — $(date)"
echo "======================================================"

# --- Identify suspect IP and MAC --------------------------------------------
if [ -n "$1" ]; then
  SUSPECT_IP="$1"
  log "Using provided suspect IP: $SUSPECT_IP"
else
  log "Scanning network to identify devices..."
  sep
  arp-scan -I "$IFACE" --localnet --ignoredups --retry=3 --timeout=2000 2>/dev/null \
    | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' \
    | nl -w2 -s') '
  sep
  read -rp "Enter the suspect IP address: " SUSPECT_IP
fi

if [ -z "$SUSPECT_IP" ]; then
  echo "[-] No IP provided. Exiting."
  exit 1
fi

# MAC: prefer explicit arg, then targeted arp-scan, then ip neigh
if [ -n "$2" ]; then
  SUSPECT_MAC="${2,,}"
  log "Using provided MAC: $SUSPECT_MAC"
else
  SUSPECT_MAC=$(arp-scan "${SUSPECT_IP}/32" --retry=5 --timeout=3000 2>/dev/null \
    | grep "^$SUSPECT_IP" | awk '{print $2}')
  # fallback: kernel neighbor table
  [ -z "$SUSPECT_MAC" ] && \
    SUSPECT_MAC=$(ip neigh show "$SUSPECT_IP" 2>/dev/null | awk '{print $5}' | grep -E '^([0-9a-f]{2}:){5}')
fi

log "Target: $SUSPECT_IP  MAC: ${SUSPECT_MAC:-(unknown)}"
sep

TMPDIR_WORK=$(mktemp -d)
trap 'rm -rf "$TMPDIR_WORK"' EXIT

# --- Phase 1: nmap OS fingerprint (runs in background) ----------------------
log "Starting nmap OS fingerprint (background)..."
nmap -O -sV --osscan-guess -T3 "$SUSPECT_IP" > "$TMPDIR_WORK/nmap.txt" 2>&1 &
NMAP_PID=$!

# --- Phase 2: mDNS capture — hostname and services (30s) -------------------
MDNS_DURATION=30
log "Capturing mDNS broadcasts for ${MDNS_DURATION}s (hostname/services)..."
timeout "$MDNS_DURATION" tcpdump -i "$IFACE" -l -n \
  "src $SUSPECT_IP and udp port 5353" 2>/dev/null \
  > "$TMPDIR_WORK/mdns_raw.txt"

# Extract hostnames: lines like "A? hostname.local" or PTR answers
MDNS_HOSTNAME=$(grep -oP '[\w\-]+\.local' "$TMPDIR_WORK/mdns_raw.txt" \
  | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')
MDNS_SERVICES=$(grep -oP '_[\w\-]+\._(?:tcp|udp)\.local' "$TMPDIR_WORK/mdns_raw.txt" \
  | sort -u | paste -sd',' -)

log "mDNS hostname: ${MDNS_HOSTNAME:-(not seen)}"
log "mDNS services: ${MDNS_SERVICES:-(none)}"

# --- Phase 3: DHCP capture — listen for any DHCP traffic from suspect -------
DHCP_DURATION=60
log "Listening for DHCP traffic for ${DHCP_DURATION}s..."
log "(If device doesn't renew in time, DHCP fingerprint will be captured by sentinel on next reconnect)"

python3 - "$IFACE" "$SUSPECT_IP" "$DHCP_DURATION" "$TMPDIR_WORK/dhcp.json" << 'PYEOF'
import socket, struct, sys, json, time, select

iface, suspect_ip, duration, outfile = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]

def parse_dhcp(data):
    if len(data) < 240:
        return None
    if data[236:240] != b'\x63\x82\x53\x63':
        return None
    options = {}
    i = 240
    while i < len(data):
        opt = data[i]
        if opt == 255: break
        if opt == 0:   i += 1; continue
        if i + 1 >= len(data): break
        ln = data[i+1]
        val = data[i+2:i+2+ln]
        options[opt] = val
        i += 2 + ln
    return options

def ip_from_bytes(b):
    return '.'.join(str(x) for x in b)

result = {}
try:
    sock = socket.socket(socket.AF_INET, socket.SOCK_RAW, socket.IPPROTO_UDP)
    # Bind to the specific interface by name (not DNS resolution)
    SO_BINDTODEVICE = 25
    sock.setsockopt(socket.SOL_SOCKET, SO_BINDTODEVICE, iface.encode() + b'\x00')
    sock.setblocking(False)
    deadline = time.time() + duration
    while time.time() < deadline:
        ready, _, _ = select.select([sock], [], [], 1.0)
        if not ready:
            continue
        pkt = sock.recv(65535)
        # IP header length
        ihl = (pkt[0] & 0x0F) * 4
        src_ip = ip_from_bytes(pkt[12:16])
        if src_ip != suspect_ip:
            continue
        # UDP: src port must be 68 (client), dst port 67 (server)
        udp = pkt[ihl:]
        if len(udp) < 8:
            continue
        src_port = struct.unpack('!H', udp[0:2])[0]
        if src_port != 68:
            continue
        payload = udp[8:]
        opts = parse_dhcp(payload)
        if not opts:
            continue
        # Option 55: parameter request list (fingerprint)
        if 55 in opts:
            result['dhcp_fingerprint'] = ','.join(str(b) for b in opts[55])
        # Option 12: hostname
        if 12 in opts:
            result['dhcp_hostname'] = opts[12].decode('utf-8', errors='replace').rstrip('\x00')
        # Option 60: vendor class identifier (OS hint)
        if 60 in opts:
            result['dhcp_vendor_class'] = opts[60].decode('utf-8', errors='replace').rstrip('\x00')
        if result:
            print(f"DHCP captured: {result}")
            break
except Exception as e:
    print(f"DHCP listener error: {e}", file=sys.stderr)

with open(outfile, 'w') as f:
    json.dump(result, f)
PYEOF

# --- Wait for nmap ----------------------------------------------------------
wait $NMAP_PID
NMAP_OS=$(grep -oP '(?<=OS details: ).*' "$TMPDIR_WORK/nmap.txt" | head -1)
NMAP_TYPE=$(grep -oP '(?<=Device type: ).*' "$TMPDIR_WORK/nmap.txt" | head -1)
[ -z "$NMAP_OS" ] && NMAP_OS=$(grep -oP '(?<=Running: ).*' "$TMPDIR_WORK/nmap.txt" | head -1)

log "nmap OS: ${NMAP_OS:-(inconclusive)}"
log "nmap device type: ${NMAP_TYPE:-(inconclusive)}"

# --- Load DHCP results and assemble profile ---------------------------------
DHCP_DATA=$(cat "$TMPDIR_WORK/dhcp.json" 2>/dev/null || echo '{}')
DHCP_FINGERPRINT=$(echo "$DHCP_DATA" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('dhcp_fingerprint',''))" 2>/dev/null)
DHCP_HOSTNAME=$(echo "$DHCP_DATA" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('dhcp_hostname',''))" 2>/dev/null)
DHCP_VENDOR=$(echo "$DHCP_DATA" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('dhcp_vendor_class',''))" 2>/dev/null)

# --- Save profile -----------------------------------------------------------
python3 - << PYEOF
import json, os
from datetime import datetime

profile = {
    "captured_at":        "$(date -Iseconds)",
    "mac":                "$SUSPECT_MAC",
    "ip_at_capture":      "$SUSPECT_IP",
    "nmap_os":            "$NMAP_OS",
    "nmap_device_type":   "$NMAP_TYPE",
    "dhcp_fingerprint":   "$DHCP_FINGERPRINT",
    "dhcp_hostname":      "$DHCP_HOSTNAME",
    "dhcp_vendor_class":  "$DHCP_VENDOR",
    "mdns_hostname":      "$MDNS_HOSTNAME",
    "mdns_services":      [s for s in "$MDNS_SERVICES".split(',') if s],
}

with open("$PROFILE_FILE", 'w') as f:
    json.dump(profile, f, indent=2)
import os, stat
os.chmod("$PROFILE_FILE", 0o644)
# transfer ownership to the real user if run via sudo
real_uid = int(os.environ.get('SUDO_UID', os.getuid()))
real_gid = int(os.environ.get('SUDO_GID', os.getgid()))
os.chown("$PROFILE_FILE", real_uid, real_gid)

print(json.dumps(profile, indent=2))
PYEOF

sep
echo ""
log "Profile saved to $PROFILE_FILE"
log "Run ./sentinel.sh to start monitoring for this device."
