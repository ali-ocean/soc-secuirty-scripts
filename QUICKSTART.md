# Quick Start Guide

## Overview
This security dashboard provides a web-based GUI for managing VM security operations across multiple hosts, similar to Ansible but focused on security hardening and compliance scanning.

## Features Summary
- **Authentication**: Secure login with Supabase (Admin & Viewer roles)
- **Host Management**: Add/edit multiple VMs with SSH connectivity
- **Security Hardening**: Automate VM and Nginx security setup remotely
- **Security Scans**: Run compliance audits and penetration tests
- **Reports**: View detailed results with PDF export
- **User Management**: Admin can control user permissions

## Quick Setup (5 minutes)

### 1. Install Dependencies
```bash
python3 -m pip install --user Flask Flask-Login Flask-WTF WTForms supabase python-dotenv paramiko xhtml2pdf
```

### 2. Start Application
```bash
python3 app.py
```

In another terminal:
```bash
python3 worker.py
```

### 3. First Login
1. Open http://localhost:5000
2. Click "Register" and create account
3. Promote yourself to admin (see below)

### 4. Promote First User to Admin

**Option A - Via Supabase Dashboard:**
1. Go to https://supabase.com/dashboard
2. Select your project
3. Navigate to Table Editor → profiles
4. Find your user and change role from 'viewer' to 'admin'

**Option B - Via SQL Editor:**
```sql
UPDATE profiles
SET role = 'admin'
WHERE email = 'your-email@example.com';
```

## Usage Workflow

### Step 1: Add Hosts
1. Login as admin
2. Navigate to **Hosts** → **Add Host**
3. Enter:
   - Hostname: `web-server-01`
   - IP Address: `192.168.1.100`
   - SSH Port: `9977` (or 22 if not hardened yet)
   - SSH User: `root`
4. Click "Add Host"

**Important**: Ensure SSH key authentication is configured for the target host.

### Step 2: Run Security Hardening
1. Navigate to **Operations** → **New Operation**
2. Select operation type:
   - **VM Hardening**: SSH, firewall, IDS, file integrity
   - **Nginx Hardening**: WAF, security headers, SSL
   - **Both**: Complete stack hardening
3. Check the hosts to harden
4. Click "Start Setup"
5. Monitor progress in Operations page

**What gets configured:**
- SSH on port 9977, key-only authentication
- UFW firewall (ports 9977, 80, 443)
- Fail2ban + CrowdSec for intrusion detection
- AIDE file integrity monitoring
- ModSecurity WAF with OWASP CRS
- Security headers (HSTS, CSP, etc.)
- And more...

### Step 3: Run Security Scans
1. Navigate to **Reports** → **Run New Scan**
2. Select scan type:
   - **Security Compliance**: Checks 17+ controls (CIS, NIST, PCI-DSS)
   - **VM Attack Test**: Simulates SSH brute-force, port scans
   - **Nginx Attack Test**: Tests WAF against SQL injection, XSS, etc.
3. Select target hosts
4. Click "Run Scan"

### Step 4: View Reports
1. Navigate to **Reports**
2. Click "View" to see detailed results
3. Click "PDF" to download report
4. Use search to filter by hostname, scan type, or status

### Step 5: Manage Users (Admin Only)
1. Navigate to **Users**
2. Change user roles:
   - **Admin**: Full control
   - **Viewer**: Read-only access + PDF downloads

## Architecture

```
┌─────────────────┐
│  Flask Web App  │ ← User Interface (localhost:5000)
│    (app.py)     │
└────────┬────────┘
         │
    ┌────▼────┐
    │Supabase │ ← Authentication + Database
    └────┬────┘
         │
┌────────▼────────┐
│ Worker Process  │ ← Background job processor
│   (worker.py)   │
└────────┬────────┘
         │
    ┌────▼────┐
    │   SSH   │ ← Remote script execution
    └─────────┘
         │
    ┌────▼────┐
    │ Target  │ ← Your VMs
    │  Hosts  │
    └─────────┘
```

## Security Scripts Included

1. **vm-secure-setup.sh**
   - SSH hardening (port 9977, keys only)
   - UFW firewall
   - Fail2ban + CrowdSec
   - AIDE file integrity
   - ClamAV + Maldet
   - Kernel hardening

2. **nginx-secure-setup.sh**
   - ModSecurity v3 WAF
   - OWASP Core Rule Set
   - Security headers (HSTS, CSP, etc.)
   - TLS 1.2+ with strong ciphers
   - Rate limiting

3. **security-scanner.sh**
   - 17 security checks
   - Compliance verification
   - Score-based grading

4. **attack-test/vm-attack-test.sh**
   - SSH brute-force test
   - Port scan detection
   - SYN flood simulation

5. **attack-test/nginx-attack-test.sh**
   - SQL injection attempts
   - XSS testing
   - Directory traversal
   - Command injection
   - RFI/XXE attacks

## Compliance Standards Covered

- **CIS Benchmarks**: SSH, firewall, system hardening
- **NIST SP 800-53**: Access control, system protection
- **PCI-DSS**: Network security, vulnerability management
- **OWASP Top 10**: Web application security
- **ISO 27001**: Information security management

## Common Issues

### SSH Key Not Configured
```bash
# Generate SSH key on dashboard server
ssh-keygen -t rsa -b 4096

# Copy to target host
ssh-copy-id -p 9977 root@192.168.1.100
```

### Port 9977 Connection Failed
If host not yet hardened, use port 22 first. After hardening, change to 9977.

### Worker Not Processing Jobs
Ensure `worker.py` is running in separate terminal. Check for errors in console output.

### Permission Denied
Ensure SSH user has sudo privileges on target host.

## User Roles

### Admin
- Add/edit/delete hosts
- Run security operations
- Execute scans
- View all reports
- Download PDFs
- Manage users

### Viewer
- View hosts (read-only)
- View all reports
- Download PDFs
- Cannot modify anything

## Tips

1. **Test on Non-Production First**: Try hardening on a test VM before production
2. **Backup SSH Access**: Keep backup SSH keys before hardening
3. **Schedule Regular Scans**: Run weekly compliance scans
4. **Review Failed Scans**: Check report details for issues
5. **Update Scripts**: Keep security scripts updated

## Next Steps

1. Add your hosts
2. Run VM hardening
3. Execute compliance scan
4. Review security score
5. Run attack tests to validate defenses
6. Invite team members (viewer role)
7. Schedule regular audits

## Support

- **Security Info Page**: In-app documentation of all tools
- **Report Issues**: Check scan output for troubleshooting
- **Supabase Logs**: View database logs for errors

## Production Deployment

For production use:
1. Use Gunicorn: `gunicorn -w 4 -b 0.0.0.0:5000 app:app`
2. Setup systemd service for worker
3. Use HTTPS with valid certificates
4. Set strong SECRET_KEY in .env
5. Enable Supabase Row Level Security
6. Use dedicated SSH service account

Enjoy your automated security operations platform!
