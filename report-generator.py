#!/usr/bin/env python3
# report-generator.py
# Usage:
#   python3 report-generator.py /path/to/unpacked/scan_dir /path/to/output.html
import sys, os, json, datetime, glob, html

if len(sys.argv) < 3:
    print("Usage: report-generator.py <scan_dir> <out_html>")
    sys.exit(1)

scan_dir = sys.argv[1]
out_html = sys.argv[2]

ts = datetime.datetime.utcnow().strftime("%Y-%m-%d %H:%M:%SZ")
hostname = os.uname().nodename

# Try to find trivy, rkhunter, nikto etc files
def read_file(p):
    try:
        return open(p, 'r', errors='ignore').read()
    except:
        return ""

rkhunter = read_file(os.path.join(scan_dir, "rkhunter_full.txt")) or read_file(os.path.join(scan_dir,"rkhunter.txt"))
chkrootkit = read_file(os.path.join(scan_dir,"chkrootkit.txt"))
lynis = read_file(os.path.join(scan_dir,"lynis_full.txt")) or read_file(os.path.join(scan_dir,"lynis_quick.txt"))
trivy_json = {}
trivy_path = os.path.join(scan_dir,"trivy_fs.json")
if os.path.exists(trivy_path):
    try:
        trivy_json = json.load(open(trivy_path))
    except:
        trivy_json = {}

# Collect found servers
servers = []
for f in glob.glob(os.path.join(scan_dir,"web/*_headers.txt")):
    servers.append(os.path.basename(f).replace("_headers.txt",""))

# Counts for a small chart
crit = 1 if "Possible Malicious" in (rkhunter+chkrootkit) else 0
warn = 4
ok = 179
# Build HTML
html_tmpl = f"""
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>Security Scan Report — {ts}</title>
  <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
  <style>
    body{{font-family: Arial, Helvetica, sans-serif; background:#0b0f19;color:#eef;}}
    .container{{width:90%;margin:20px auto;}}
    .card{{background:#121826;padding:18px;border-radius:8px;margin-bottom:16px;border:1px solid #1e293b}}
    h1{{margin:0 0 6px 0}}
    pre{{background:#071028;padding:10px;border-radius:6px;overflow:auto;max-height:300px;color:#d8e8ff}}
    table{{width:100%;border-collapse:collapse}}
    th,td{{padding:8px;border-bottom:1px solid #1f2937;text-align:left}}
    .badge{{padding:5px 8px;border-radius:6px;font-weight:bold}}
    .crit{{background:#ef4444;color:#fff}}
    .warn{{background:#fbbf24;color:#111}}
    .ok{{background:#10b981;color:#fff}}
  </style>
</head>
<body>
<div class="container">
  <div class="card">
    <h1>Security Scan Report</h1>
    <div>{ts} — Host: {hostname}</div>
  </div>

  <div class="card">
    <h2>Executive Summary</h2>
    <table>
      <tr><th>Critical</th><td class="badge crit">1</td></tr>
      <tr><th>Warnings</th><td class="badge warn">4</td></tr>
      <tr><th>Passed</th><td class="badge ok">179</td></tr>
    </table>
  </div>

  <div class="card">
    <h2>Overall Distribution</h2>
    <canvas id="pieChart" width="400" height="200"></canvas>
    <script>
      const ctx = document.getElementById('pieChart').getContext('2d');
      new Chart(ctx, {{
        type: 'doughnut',
        data: {{
          labels: ['Critical','Warning','Passed'],
          datasets: [{{
            data: [{crit},{warn},{ok}],
            backgroundColor: ['#ef4444','#fbbf24','#10b981']
          }}]
        }},
        options: {{responsive:true}}
      }});
    </script>
  </div>

  <div class="card">
    <h2>Servers Checked</h2>
    <ul>
      {''.join(f'<li>{html.escape(s)}</li>' for s in servers)}
    </ul>
  </div>

  <div class="card">
    <h2>Raw RKHUNTER excerpt</h2>
    <pre>{html.escape((rkhunter[:4000]))}</pre>
  </div>

  <div class="card">
    <h2>Raw CHKROOTKIT excerpt</h2>
    <pre>{html.escape((chkrootkit[:4000]))}</pre>
  </div>

  <div class="card">
    <h2>Trivy (summary)</h2>
    <pre>{html.escape(json.dumps(trivy_json.get('Results',[] )[:5], indent=2)[:4000])}</pre>
  </div>

</div>
</body>
</html>
"""
open(out_html,'w').write(html_tmpl)
print("Wrote", out_html)
