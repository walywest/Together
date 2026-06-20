#!/usr/bin/env bash
#
# Network device census — counts how many devices are connected to the LAN.
# Aggregates several discovery methods and dedupes by MAC address so a device
# that misses one probe (asleep, slow, quiet) still gets counted.

if [ "$EUID" -ne 0 ]; then
  exec sudo env PATH="$PATH" "$0" "$@"
fi

if ! command -v arp-scan &> /dev/null; then
  echo "[-] 'arp-scan' is not available. Run from devenv: direnv exec . $0"
  exit 1
fi

# --- config -----------------------------------------------------------------
NUM_ROUNDS=${NUM_ROUNDS:-3}      # active ARP scan passes to union together
PASSIVE_DURATION=${PASSIVE_DURATION:-15}  # seconds of passive capture (0=skip)
# ----------------------------------------------------------------------------

IFACE=$(ip route | awk '/default/ {print $5; exit}')
GW_IP=$(ip route | awk '/default/ {print $3; exit}')
SELF_IP=$(ip -4 addr show dev "$IFACE" | awk '/inet / {print $2}' | cut -d/ -f1)
SELF_MAC=$(cat "/sys/class/net/$IFACE/address" 2>/dev/null)
SELF_MAC="${SELF_MAC,,}"

# Accumulator: one line per device "MAC<TAB>IP<TAB>VENDOR<TAB>SOURCES"
SEEN=$(mktemp)
trap 'rm -f "$SEEN"' EXIT

# record MAC IP VENDOR SOURCE — merges into the accumulator, tracking sources
record() {
  local mac="${1,,}" ip="$2" vendor="$3" src="$4"
  [ -z "$mac" ] && return
  # never count this machine itself
  [ -n "$SELF_MAC" ] && [ "$mac" = "$SELF_MAC" ] && return
  [ -n "$SELF_IP" ] && [ "$ip" = "$SELF_IP" ] && return
  local existing
  existing=$(grep -i "^$mac	" "$SEEN")
  if [ -n "$existing" ]; then
    # already known — keep existing IP/vendor, just append source tag if new
    local e_ip e_vendor srcs
    e_ip=$(echo "$existing" | cut -f2)
    e_vendor=$(echo "$existing" | cut -f3)
    srcs=$(echo "$existing" | cut -f4)
    # prefer a real vendor string if we now have one and didn't before
    [ "$e_vendor" = "(Unknown)" ] && [ -n "$vendor" ] && e_vendor="$vendor"
    case ",$srcs," in
      *",$src,"*) srcs="$srcs" ;;       # already recorded this source
      *) srcs="$srcs,$src" ;;
    esac
    sed -i "s|^$mac	.*|$mac	$e_ip	$e_vendor	$srcs|I" "$SEEN"
  else
    printf '%s\t%s\t%s\t%s\n' "$mac" "$ip" "${vendor:-(Unknown)}" "$src" >> "$SEEN"
  fi
}

echo "======================================================"
echo "[*] Network device census — $(date)"
echo "[*] Interface: $IFACE"
echo "======================================================"

# --- Source 1: active ARP scan, multiple passes -----------------------------
for round in $(seq 1 "$NUM_ROUNDS"); do
  echo "[*] ARP scan pass $round/$NUM_ROUNDS..."
  while IFS=$'\t' read -r ip mac vendor; do
    record "$mac" "$ip" "$vendor" "arp"
  done < <(arp-scan -I "$IFACE" --localnet --ignoredups --retry=2 --timeout=1500 \
             | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')
done

# --- Source 2: kernel neighbor (ARP) table, REACHABLE only ------------------
# Only count entries the kernel has confirmed alive within its reachable window
# (~30s). STALE entries are excluded — those may be devices that already left.
echo "[*] Reading kernel neighbor table (REACHABLE only)..."
while read -r ip _ _ _ mac state; do
  [[ "$mac" =~ ^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$ ]] || continue
  [[ "$state" == "REACHABLE" ]] || continue
  record "$mac" "$ip" "" "neigh"
done < <(ip neigh show dev "$IFACE")

# --- Source 3: passive ARP capture ------------------------------------------
if [ "$PASSIVE_DURATION" -gt 0 ] && command -v tcpdump &> /dev/null; then
  echo "[*] Passive capture (${PASSIVE_DURATION}s)..."
  while read -r ip mac; do
    record "$mac" "$ip" "" "passive"
  done < <(timeout "$PASSIVE_DURATION" tcpdump -i "$IFACE" -l -n -e arp 2>/dev/null \
    | awk '
        # tcpdump -e prints "<srcmac> > ... ARP, Reply <ip> is-at <mac>"
        /ARP, Reply/ {
          for (i=1; i<=NF; i++)
            if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) { ip=$i; break }
          for (i=1; i<=NF; i++)
            if ($i ~ /^([0-9a-f]{2}:){5}[0-9a-f]{2}$/) { mac=$i }
          if (ip && mac) print ip, mac
        }')
fi

# --- Report -----------------------------------------------------------------
echo "--------------------------------------------------"
printf "%-16s %-18s %-8s %s\n" "IP" "MAC" "SOURCES" "VENDOR"
echo "--------------------------------------------------"
sort -t$'\t' -k2 -V "$SEEN" | while IFS=$'\t' read -r mac ip vendor srcs; do
  tag=""
  [ "$ip" = "$GW_IP" ] && tag="  <- gateway/router"
  printf "%-16s %-18s %-8s %s%s\n" "$ip" "$mac" "$srcs" "$vendor" "$tag"
done
echo "--------------------------------------------------"

total=$(wc -l < "$SEEN")
# is the gateway among the discovered devices?
gw_found=0
grep -q "	$GW_IP	" "$SEEN" && gw_found=1
others=$((total - gw_found))

echo "[*] This machine ($SELF_IP / $SELF_MAC) is excluded from the count."
if [ "$gw_found" -eq 1 ]; then
  echo "[*] Gateway/router ($GW_IP) detected and listed, but excluded from the device count."
fi
echo "[+] Other devices on the network: $others"
echo "    (deduplicated by MAC across $NUM_ROUNDS ARP passes + REACHABLE neighbors + passive capture)"
