#!/usr/bin/env bash
# baseline-security-scan.sh
set -euo pipefail
TS=$(date +%F_%H%M%S)
OUT="/tmp/sec_scan_${TS}"
mkdir -p "$OUT"
echo "Baseline scan started at $(date)" > "$OUT/run.log"

# 1) System facts
uname -a > "$OUT/uname.txt"
lsb_release -a > "$OUT/lsb.txt" 2>/dev/null || true
df -h > "$OUT/df.txt"
free -m > "$OUT/mem.txt"

# 2) Security tools quick
echo "Running rkhunter, chkrootkit (quick)..." >> "$OUT/run.log"
rkhunter --check --sk --quiet > "$OUT/rkhunter.txt" 2>&1 || true
chkrootkit > "$OUT/chkrootkit.txt" 2>&1 || true

# 3) Fail2ban & CrowdSec status
systemctl is-active --quiet fail2ban && echo "fail2ban active" > "$OUT/fail2ban.status" || echo "fail2ban inactive" > "$OUT/fail2ban.status"
if command -v cscli >/dev/null 2>&1; then
  cscli decisions list --format json > "$OUT/crowdsec_decisions.json" 2>/dev/null || true
  cscli metrics > "$OUT/crowdsec_metrics.txt" 2>/dev/null || true
fi

# 4) AIDE quick check (if DB present)
if [ -f /var/lib/aide/aide.db ]; then
  aide --check > "$OUT/aide_check.txt" 2>&1 || true
else
  echo "AIDE DB missing" > "$OUT/aide_missing.txt"
fi

# 5) Root of web server: find server_names
NGINX_CONFS="/etc/nginx/sites-enabled /etc/nginx/conf.d"
SERVERS_FILE="$OUT/servers.list"
> "$SERVERS_FILE"
for d in /etc/nginx/sites-enabled /etc/nginx/conf.d; do
  [ -d "$d" ] || continue
  for f in "$d"/*; do
    [ -f "$f" ] || continue
    grep -i "server_name" "$f" 2>/dev/null | sed 's/.*server_name//' | tr -d ';' | tr -s ' ' '\n' | while read -r host; do
      host=$(echo "$host" | xargs)
      if [ -n "$host" ]; then echo "$host" >> "$SERVERS_FILE"; fi
    done
  done
done

# if none found, default localhost
if [ ! -s "$SERVERS_FILE" ]; then
  echo "localhost" > "$SERVERS_FILE"
fi

# 6) For each server, run curl -I and TLS check
OUT_WEB="$OUT/web"
mkdir -p "$OUT_WEB"
while read -r target; do
  safe=$(echo "$target" | sed 's/[^A-Za-z0-9_.-]/_/g')
  echo "Checking $target" >> "$OUT/run.log"
  # HTTP header check
  curl -k -I -sS "https://$target" -o "$OUT_WEB/${safe}_headers.txt" || curl -k -I -sS "http://$target" -o "$OUT_WEB/${safe}_headers.txt" || echo "curl failed" > "$OUT_WEB/${safe}_curl.err"
  # Check for security headers
  grep -i "Strict-Transport-Security\|X-Frame-Options\|X-Content-Type-Options\|X-XSS-Protection\|Referrer-Policy" "$OUT_WEB/${safe}_headers.txt" > "$OUT_WEB/${safe}_sec_headers.txt" || true
  # TLS summary via openssl (if HTTPS)
  echo | timeout 10 openssl s_client -connect "${target}:443" -servername "${target}" 2>/dev/null | sed -n '1,120p' > "$OUT_WEB/${safe}_openssl.txt" || true
done < "$SERVERS_FILE"

# 7) Produce JSON summary
jq -n --arg ts "$TS" --slurpfile servers "$SERVERS_FILE" \
  '{timestamp:$ts,hostname:env.HOSTNAME,servers:$servers[0]}' > "$OUT/summary.json"

# 8) Archive outputs to tar (easier to copy)
tar -czf "/tmp/sec_scan_${TS}.tar.gz" -C /tmp "sec_scan_${TS}" || true
echo "Baseline scan finished: $OUT" >> "$OUT/run.log"
echo "/tmp/sec_scan_${TS}.tar.gz" > "$OUT/SCAN_TAR"
