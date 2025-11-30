#!/usr/bin/env bash
# runner.sh (SOC VM orchestrator)
set -euo pipefail
BASE="/root/scripts"
REPORTS_DIR="$BASE/reports"
mkdir -p "$REPORTS_DIR/server_reports" "$REPORTS_DIR/nginx_reports"

echo "=== SEC OPS RUNNER ==="
PS3="Choose an action: "
OPTIONS=("Setup and secure VM" "Run baseline scan" "Run enterprise scan" "Exit")
select opt in "${OPTIONS[@]}"; do
  case $REPLY in
    1)
      echo "Enter target IP or hostname (use 'localhost' to run locally):"
      read -r TARGET
      echo "Do you want to copy this SOC server's public key to the target for passwordless SSH? (y/n)"
      read -r COPYKEY
      if [ "$COPYKEY" = "y" ] || [ "$COPYKEY" = "Y" ]; then
        # ensure local key exists
        if [ ! -f ~/.ssh/id_rsa.pub ]; then
          echo "No id_rsa.pub found; generating key..."
          ssh-keygen -t rsa -b 4096 -N "" -f ~/.ssh/id_rsa
        fi
        if [ "$TARGET" != "localhost" ]; then
          echo "Copying public key to $TARGET (you will be prompted for password)..."
          ssh-copy-id -i ~/.ssh/id_rsa.pub "root@$TARGET" || echo "ssh-copy-id failed; you can copy manually."
        else
          echo "Skipping copy key for localhost."
        fi
      fi

      # prepare remote dir and copy scripts
      if [ "$TARGET" = "localhost" ]; then
        echo "Running on local host..."
        bash "$BASE/vm-secure-setup.sh" | tee -a /var/log/runner_vm_setup.log
        # check for nginx and run nginx secure if present
        if command -v nginx >/dev/null 2>&1; then
          echo "Nginx detected locally; running nginx-secure-setup.sh"
          bash "$BASE/nginx-secure-setup.sh" | tee -a /var/log/runner_nginx_setup.log
        else
          echo "Nginx not detected locally; skipping nginx setup."
        fi
      else
        # remote flow
        echo "Preparing remote host $TARGET..."
        ssh -o BatchMode=yes -o StrictHostKeyChecking=no "root@$TARGET" "mkdir -p /tmp/sec-setup" || true
        scp -o StrictHostKeyChecking=no "$BASE/vm-secure-setup.sh" "root@$TARGET:/tmp/sec-setup/" || true
        scp -o StrictHostKeyChecking=no "$BASE/nginx-secure-setup.sh" "root@$TARGET:/tmp/sec-setup/" || true

        echo "Executing vm-secure-setup.sh remotely on $TARGET (streaming output)..."
        ssh -t -o StrictHostKeyChecking=no "root@$TARGET" "bash /tmp/sec-setup/vm-secure-setup.sh" | tee -a /var/log/runner_vm_setup.log

        echo "Check if nginx present remotely..."
        if ssh -o StrictHostKeyChecking=no "root@$TARGET" "command -v nginx >/dev/null 2>&1"; then
          echo "Running nginx-secure-setup.sh on $TARGET..."
          ssh -t -o StrictHostKeyChecking=no "root@$TARGET" "bash /tmp/sec-setup/nginx-secure-setup.sh" | tee -a /var/log/runner_nginx_setup.log
        else
          echo "Nginx not found on $TARGET; skipped nginx hardening."
        fi

        # cleanup remote staging
        ssh -o StrictHostKeyChecking=no "root@$TARGET" "rm -rf /tmp/sec-setup"
      fi
      ;;
    2)
      echo "Enter target IP or hostname (use 'localhost' to run locally):"
      read -r TARGET
      if [ "$TARGET" = "localhost" ]; then
        echo "Running baseline scan locally..."
        bash "$BASE/baseline-security-scan.sh"
        TAR=$(ls -1 /tmp/sec_scan_*.tar.gz | tail -n1)
        echo "Copying report into $REPORTS_DIR/server_reports"
        mkdir -p "$REPORTS_DIR/server_reports/$(date +%F_%H%M%S)"
        tar -xzf "$TAR" -C "$REPORTS_DIR/server_reports/$(date +%F_%H%M%S)" || true
        # generate HTML report on SOC
        python3 "$BASE/report-generator.py" "$REPORTS_DIR/server_reports/"$(ls -1 "$REPORTS_DIR/server_reports"| tail -n1) "$REPORTS_DIR/server_reports/$(ls -1 "$REPORTS_DIR/server_reports"| tail -n1)/report.html"
        echo "Baseline scan complete. Report at $REPORTS_DIR/server_reports/$(ls -1 "$REPORTS_DIR/server_reports"| tail -n1)/report.html"
      else
        echo "Copying scan scripts to remote..."
        ssh -o StrictHostKeyChecking=no "root@$TARGET" "mkdir -p /tmp/sec-scan"
        scp -o StrictHostKeyChecking=no "$BASE/baseline-security-scan.sh" "root@$TARGET:/tmp/sec-scan/" || true
        echo "Executing baseline scan remotely..."
        ssh -t -o StrictHostKeyChecking=no "root@$TARGET" "bash /tmp/sec-scan/baseline-security-scan.sh" | tee -a /var/log/runner_scan.log
        # fetch tar and pull into reports dir
        TAR_PATH=$(ssh -o StrictHostKeyChecking=no "root@$TARGET" "cat /tmp/sec_scan_*/SCAN_TAR 2>/dev/null || true" )
        if [ -n "$TAR_PATH" ]; then
          echo "Remote produced tar: $TAR_PATH"
          mkdir -p "$REPORTS_DIR/server_reports/$(date +%F_%H%M%S)"
          scp -o StrictHostKeyChecking=no "root@$TARGET:$TAR_PATH" "$REPORTS_DIR/server_reports/$(ls -1 "$REPORTS_DIR/server_reports"| tail -n1)/" || true
          # extract
          tar -xzf "$REPORTS_DIR/server_reports/$(ls -1 "$REPORTS_DIR/server_reports"| tail -n1)/$(basename $TAR_PATH)" -C "$REPORTS_DIR/server_reports/$(ls -1 "$REPORTS_DIR/server_reports"| tail -n1)/" || true
          # generate HTML
          python3 "$BASE/report-generator.py" "$(ls -1 -d $REPORTS_DIR/server_reports/* | tail -n1)/$(basename $(tar -tzf $REPORTS_DIR/server_reports/*/*.tar.gz | head -n1) 2>/dev/null || true)" "$REPORTS_DIR/server_reports/$(ls -1 "$REPORTS_DIR/server_reports"| tail -n1)/report.html" 2>/dev/null || true
          echo "Report copied to $REPORTS_DIR/server_reports/$(ls -1 "$REPORTS_DIR/server_reports"| tail -n1)/"
        else
          echo "Could not find remote tar path; check remote scan logs."
        fi
      fi
      ;;
    3)
      echo "Enter target IP or hostname (use 'localhost' to run locally):"
      read -r TARGET
      if [ "$TARGET" = "localhost" ]; then
        echo "Running enterprise scan locally (heavy, may take long)..."
        bash "$BASE/enterprise-security-scan.sh"
        TAR=$(ls -1 /tmp/sec_scan_*.tar.gz | tail -n1)
        echo "Copying report into $REPORTS_DIR/server_reports"
        mkdir -p "$REPORTS_DIR/server_reports/$(date +%F_%H%M%S)"
        tar -xzf "$TAR" -C "$REPORTS_DIR/server_reports/$(date +%F_%H%M%S)" || true
        python3 "$BASE/report-generator.py" "$REPORTS_DIR/server_reports/$(ls -1 "$REPORTS_DIR/server_reports"| tail -n1)" "$REPORTS_DIR/server_reports/$(ls -1 "$REPORTS_DIR/server_reports"| tail -n1)/report.html"
        echo "Enterprise scan complete. Report at $REPORTS_DIR/server_reports/$(ls -1 "$REPORTS_DIR/server_reports"| tail -n1)/report.html"
      else
        ssh -o StrictHostKeyChecking=no "root@$TARGET" "mkdir -p /tmp/sec-scan"
        scp -o StrictHostKeyChecking=no "$BASE/enterprise-security-scan.sh" "root@$TARGET:/tmp/sec-scan/" || true
        echo "Executing enterprise scan remotely..."
        ssh -t -o StrictHostKeyChecking=no "root@$TARGET" "bash /tmp/sec-scan/enterprise-security-scan.sh" | tee -a /var/log/runner_scan.log
        TAR_PATH=$(ssh -o StrictHostKeyChecking=no "root@$TARGET" "cat /tmp/sec_scan_*/SCAN_TAR 2>/dev/null || true" )
        if [ -n "$TAR_PATH" ]; then
          mkdir -p "$REPORTS_DIR/server_reports/$(date +%F_%H%M%S)"
          scp -o StrictHostKeyChecking=no "root@$TARGET:$TAR_PATH" "$REPORTS_DIR/server_reports/$(ls -1 "$REPORTS_DIR/server_reports"| tail -n1)/" || true
          tar -xzf "$REPORTS_DIR/server_reports/$(ls -1 "$REPORTS_DIR/server_reports"| tail -n1)/*" -C "$REPORTS_DIR/server_reports/$(ls -1 "$REPORTS_DIR/server_reports"| tail -n1)/" || true
          python3 "$BASE/report-generator.py" "$(ls -1 -d $REPORTS_DIR/server_reports/* | tail -n1)" "$(ls -1 -d $REPORTS_DIR/server_reports/* | tail -n1)/report.html" 2>/dev/null || true
          echo "Enterprise report copied to $REPORTS_DIR/server_reports/$(ls -1 "$REPORTS_DIR/server_reports"| tail -n1)/"
        else
          echo "Could not find remote tar path; check remote scan logs."
        fi
      fi
      ;;
    4)
      echo "Bye"; break;;
    *)
      echo "Invalid option";;
  esac
done
