#!/usr/bin/env bash
# enterprise-security-scan.sh
set -euo pipefail
TS=$(date +%F_%H%M%S)
OUT="/tmp/sec_scan_${TS}"
mkdir -p "$OUT"
echo "Enterprise scan started at $(date)" > "$OUT/run.log"

# System facts
uname -a > "$OUT/uname.txt"
lsb_release -a > "$OUT/lsb.txt" 2>/dev/null || true
df -h > "$OUT/df.txt"
free -m > "$OUT/mem.txt"

# Lynis full audit (quiet)
lynis audit system --quiet > "$OUT/lynis_full.txt" 2>&1 || true

# rkhunter & chkrootkit
rkhunter --update || true
rkhunter --propupd || true
rkhunter --check --sk --nolog > "$OUT/rkhunter_full.txt" 2>&1 || true
chkrootkit > "$OUT/chkrootkit.txt" 2>&1 || true

# Maldet (scan /var/www and /tmp)
if command -v maldet >/dev/null 2>&1; then
  maldet --scan-all /var/www --report > "$OUT/maldet_www.txt" 2>&1 || true
  maldet --scan-all /tmp --report > "$OUT/maldet_tmp.txt" 2>&1 || true
fi

# ClamAV deep scan (may be slow)
if command -v clamscan >/dev/null 2>&1; then
  clamscan -ri /var/www > "$OUT/clamav_www.txt" 2>&1 || true
fi

# Trivy FS (requires trivy installed)
if command -v trivy >/dev/null 2>&1; then
  trivy fs --severity CRITICAL,HIGH --format json -o "$OUT/trivy_fs.json" / || true
fi

# Gather kernel modules & processes
lsmod > "$OUT/lsmod.txt"
ps aux > "$OUT/psaux.txt"

# Web tests (same as baseline but also run nikto)
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
if [ ! -s "$SERVERS_FILE" ]; then echo "localhost" > "$SERVERS_FILE"; fi

OUT_WEB="$OUT/web"
mkdir -p "$OUT_WEB"
while read -r target; do
  safe=$(echo "$target" | sed 's/[^A-Za-z0-9_.-]/_/g')
  curl -k -I -sS "https://$target" -o "$OUT_WEB/${safe}_headers.txt" || curl -k -I -sS "http://$target" -o "$OUT_WEB/${safe}_headers.txt" || true
  grep -i "Strict-Transport-Security\|X-Frame-Options\|X-Content-Type-Options\|X-XSS-Protection\|Referrer-Policy" "$OUT_WEB/${safe}_headers.txt" > "$OUT_WEB/${safe}_sec_headers.txt" || true
  echo | timeout 15 openssl s_client -connect "${target}:443" -servername "${target}" 2>/dev/null | sed -n '1,200p' > "$OUT_WEB/${safe}_openssl.txt" || true
  # run nikto non-intrusive
  if command -v nikto >/dev/null 2>&1; then
    nikto -host "https://$target" -output "$OUT_WEB/${safe}_nikto.txt" -timeout 30 || true
  fi
done < "$SERVERS_FILE"

# Produce JSON summary
jq -n --arg ts "$TS" --arg host "$(hostname -f)" '{timestamp:$ts,host:$host}' > "$OUT/summary.json"

# Tar outputs
tar -czf "/tmp/sec_scan_${TS}.tar.gz" -C /tmp "sec_scan_${TS}" || true
echo "/tmp/sec_scan_${TS}.tar.gz" > "$OUT/SCAN_TAR"
echo "Enterprise scan finished: $OUT" >> "$OUT/run.log"
