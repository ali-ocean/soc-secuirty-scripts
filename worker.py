import os
import time
import paramiko
import subprocess
from datetime import datetime
from supabase import create_client, Client
from dotenv import load_dotenv
import re

load_dotenv()

supabase_url = os.getenv('VITE_SUPABASE_URL')
supabase_key = os.getenv('VITE_SUPABASE_SUPABASE_ANON_KEY')
supabase: Client = create_client(supabase_url, supabase_key)

def execute_remote_script(host, script_path, script_content):
    try:
        ssh = paramiko.SSHClient()
        ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())

        ssh.connect(
            hostname=host['ip_address'],
            port=host['ssh_port'],
            username=host['ssh_user'],
            timeout=30
        )

        remote_script = f"/tmp/security_script_{int(time.time())}.sh"
        sftp = ssh.open_sftp()
        with sftp.file(remote_script, 'w') as f:
            f.write(script_content)
        sftp.chmod(remote_script, 0o755)
        sftp.close()

        stdin, stdout, stderr = ssh.exec_command(f'bash {remote_script}', timeout=1800)
        output = stdout.read().decode('utf-8')
        error = stderr.read().decode('utf-8')

        ssh.exec_command(f'rm {remote_script}')
        ssh.close()

        return output, error, None
    except Exception as e:
        return '', '', str(e)

def process_setup_operations():
    try:
        pending = supabase.table('setup_operations').select('*, hosts(*)').eq('status', 'pending').execute()

        for op in pending.data or []:
            print(f"Processing setup operation {op['id']} for host {op['hosts']['hostname']}")

            supabase.table('setup_operations').update({
                'status': 'running',
                'started_at': datetime.utcnow().isoformat()
            }).eq('id', op['id']).execute()

            script_content = ''
            if op['operation_type'] == 'vm_hardening' or op['operation_type'] == 'both':
                with open('vm-secure-setup.sh', 'r') as f:
                    script_content += f.read() + '\n'

            if op['operation_type'] == 'nginx_hardening' or op['operation_type'] == 'both':
                with open('nginx-secure-setup.sh', 'r') as f:
                    script_content += f.read() + '\n'

            output, error, exception = execute_remote_script(
                op['hosts'],
                'setup_script.sh',
                script_content
            )

            if exception:
                supabase.table('setup_operations').update({
                    'status': 'failed',
                    'error_message': exception,
                    'completed_at': datetime.utcnow().isoformat()
                }).eq('id', op['id']).execute()
            else:
                full_output = output + ('\n' + error if error else '')
                supabase.table('setup_operations').update({
                    'status': 'completed',
                    'output': full_output,
                    'completed_at': datetime.utcnow().isoformat()
                }).eq('id', op['id']).execute()

                supabase.table('hosts').update({
                    'status': 'active',
                    'updated_at': datetime.utcnow().isoformat()
                }).eq('id', op['host_id']).execute()

    except Exception as e:
        print(f"Error processing setup operations: {e}")

def process_scan_reports():
    try:
        pending = supabase.table('scan_reports').select('*, hosts(*)').eq('status', 'pending').execute()

        for report in pending.data or []:
            print(f"Processing scan {report['id']} for host {report['hosts']['hostname']}")

            supabase.table('scan_reports').update({
                'status': 'running',
                'started_at': datetime.utcnow().isoformat()
            }).eq('id', report['id']).execute()

            script_map = {
                'security': 'security-scanner.sh',
                'vm_attack': 'attack-test/vm-attack-test.sh',
                'nginx_attack': 'attack-test/nginx-attack-test.sh'
            }

            script_file = script_map.get(report['scan_type'])
            if not script_file:
                supabase.table('scan_reports').update({
                    'status': 'failed',
                    'error_message': 'Unknown scan type',
                    'completed_at': datetime.utcnow().isoformat()
                }).eq('id', report['id']).execute()
                continue

            with open(script_file, 'r') as f:
                script_content = f.read()

            output, error, exception = execute_remote_script(
                report['hosts'],
                script_file.split('/')[-1],
                script_content
            )

            if exception:
                supabase.table('scan_reports').update({
                    'status': 'failed',
                    'error_message': exception,
                    'completed_at': datetime.utcnow().isoformat()
                }).eq('id', report['id']).execute()
            else:
                full_output = output + ('\n' + error if error else '')

                html_report = None
                score = None
                passed = 0
                total = 0

                html_match = re.search(r'<!DOCTYPE html>.*</html>', full_output, re.DOTALL)
                if html_match:
                    html_report = html_match.group(0)

                    score_match = re.search(r'Score:\s*(\d+)%', html_report)
                    if score_match:
                        score = int(score_match.group(1))

                    passed_match = re.search(r'Pass:\s*(\d+)', html_report)
                    if passed_match:
                        passed = int(passed_match.group(1))

                    total_match = re.search(r'Total:\s*(\d+)', html_report)
                    if total_match:
                        total = int(total_match.group(1))

                supabase.table('scan_reports').update({
                    'status': 'completed',
                    'html_report': html_report,
                    'scan_output': full_output,
                    'score': score,
                    'passed_checks': passed,
                    'total_checks': total,
                    'completed_at': datetime.utcnow().isoformat()
                }).eq('id', report['id']).execute()

                supabase.table('hosts').update({
                    'last_scan_at': datetime.utcnow().isoformat(),
                    'updated_at': datetime.utcnow().isoformat()
                }).eq('id', report['host_id']).execute()

    except Exception as e:
        print(f"Error processing scan reports: {e}")

def main():
    print("Security Dashboard Worker Started")
    print("Monitoring for pending operations and scans...")

    while True:
        try:
            process_setup_operations()
            process_scan_reports()
            time.sleep(10)
        except KeyboardInterrupt:
            print("\nWorker stopped")
            break
        except Exception as e:
            print(f"Worker error: {e}")
            time.sleep(10)

if __name__ == '__main__':
    main()
