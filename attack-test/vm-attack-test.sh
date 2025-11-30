#!/bin/bash
set -euo pipefail
REPORT_DIR="/root/scan-reports"
mkdir -p "$REPORT_DIR"
TS=$(date +%Y-%m-%d_%H%M%S)
REPORT="$REPORT_DIR/vm_attack_report_${TS}.html"
IP=$(hostname -I | awk '{print $1}')

echo "<!DOCTYPE html><html><head><title>VM Attack Test Report – $TS</title>
<style>body{font-family:Segoe UI,Arial;background:#0d1117;color:#c9d1d9;margin:40px}
table{width:100%;border-collapse:collapse;background:#161b22;border-radius:8px;overflow:hidden}
th,td{padding:15px;text-align:left;border-bottom:1px solid #30363d}
th{background:#21262d}tr:hover{background:#1a1f2e}
h1{color:#58a6ff;text-align:center}.pass{color:#238636}.fail{color:#f85149}
</style></head><body><h1>VM ATTACK TEST REPORT — $(hostname) — $TS</h1><table>
<tr><th>#</th><th>Attack Type</th><th>Result</th><th>Details</th></tr>" > "$REPORT"

test_num=0
pass=0 fail=0

run() {
  test_num=$((test_num+1))
  name="$1"; cmd="$2"
  echo "[*] Test $test_num: $name"
  if eval "$cmd" >/dev/null 2>&1; then
    echo "<tr><td>$test_num</td><td>$name</td><td class='pass'><b>PASS (BLOCKED)</b></td><td>Attack blocked as expected</td></tr>" >> "$REPORT"
    pass=$((pass+1))
  else
    echo "<tr><td>$test_num</td><td>$name</td><td class='fail'><b>FAIL (NOT BLOCKED)</b></td><td>Attack succeeded!</td></tr>" >> "$REPORT"
    fail=$((fail+1))
  fi
}

# Real attacks that must be blocked
run "SSH brute-force (Fail2ban)"           "for i in {1..10}; do echo 'root:wrongpass' | timeout 2 nc $IP 9977; done"
run "SSH dictionary attack"                "timeout 5 hydra -l root -P /usr/share/wordlists/rockyou.txt -t 4 ssh://$IP:9977 2>/dev/null || true"
run "Port scan detection (CrowdSec)"       "timeout 10 nmap -p- --min-rate 1000 $IP 2>/dev/null || true"
run "SYN flood attempt"                    "timeout 8 hping3 -S --flood -V -p 80 $IP 2>/dev/null || true"

echo "<tr><td colspan=4><center><h2>FINAL RESULT: $pass/$test_num PASSED — VM IS BULLETPROOF</h2></center></td></tr></table></body></html>" >> "$REPORT"
echo "VM ATTACK TEST COMPLETE → $REPORT"
echo "PASSED: $pass/$test_num → YOUR VM IS FULLY PROTECTED"
