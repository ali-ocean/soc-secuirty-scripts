# Security Dashboard - VM Security Audit Application

Enterprise-grade security dashboard for managing VM security hardening, compliance scanning, and attack testing across multiple hosts.

## Features

### Authentication & Authorization
- Supabase-powered authentication
- Role-based access control (Admin / Viewer)
- Admin: Full control over hosts, scans, operations, and users
- Viewer: Read-only access to reports with PDF download capability

### Host Management
- Add and manage multiple remote hosts
- Track host status, IP addresses, SSH ports
- Centralized inventory of all security-managed systems

### Security Operations

#### VM Hardening
- SSH hardening (port 9977, key-only auth, root disabled)
- UFW firewall configuration
- Fail2ban intrusion prevention
- CrowdSec threat intelligence
- AIDE file integrity monitoring
- Kernel hardening (sysctl)
- ClamAV + Maldet malware detection
- Automatic security updates

#### Nginx Hardening
- ModSecurity v3 Web Application Firewall
- OWASP Core Rule Set (CRS)
- Security headers (HSTS, CSP, X-Frame-Options, etc.)
- SSL/TLS hardening (TLS 1.2+, strong ciphers)
- Rate limiting protection
- Server version hiding

### Security Scanning

#### Security Compliance Scan
- 17+ security control checks
- CIS Benchmark compliance
- NIST SP 800-53 controls
- PCI-DSS requirements
- OWASP standards
- Detailed HTML reports with scores

#### VM Attack Testing
- SSH brute-force simulation
- Dictionary attack testing
- Port scan detection validation
- SYN flood testing
- Verifies IDS/IPS functionality

#### Nginx WAF Attack Testing
- SQL injection attempts
- XSS payload testing
- Directory traversal
- Command injection
- Remote file inclusion
- XXE attacks
- Validates WAF blocking capabilities

### Report Management
- Comprehensive search and filtering
- View detailed scan results
- Download reports as PDF
- Historical tracking of all scans
- Score-based security grading

### Security Information
- Complete documentation of all security tools
- Functionality descriptions
- Compliance mappings (CIS, NIST, PCI-DSS, OWASP, ISO 27001)
- Best practices reference

## Installation

### Prerequisites
```bash
# Python 3.8+
# SSH key access to target hosts
# Supabase account
```

### Setup

1. Install dependencies:
```bash
pip install -r requirements.txt
```

2. Configure environment variables:
```bash
# .env file already contains Supabase credentials
# Add SECRET_KEY if needed
SECRET_KEY=your-secret-key-here
```

3. Database is already configured with Supabase

4. Start the Flask application:
```bash
python app.py
```

5. Start the background worker (in a separate terminal):
```bash
python worker.py
```

6. Access the dashboard at `http://localhost:5000`

### First User Setup
1. Register at `/register`
2. First user will be created as 'viewer'
3. Manually promote to 'admin' via Supabase dashboard or SQL:
```sql
UPDATE profiles SET role = 'admin' WHERE email = 'your-email@example.com';
```

## Usage

### Adding Hosts
1. Navigate to "Hosts" → "Add Host"
2. Enter hostname, IP address, SSH port (default 9977), SSH user
3. Ensure SSH key authentication is configured

### Running Security Hardening
1. Navigate to "Operations" → "New Operation"
2. Select hardening type (VM, Nginx, or Both)
3. Select target hosts
4. Monitor progress in Operations page

### Running Security Scans
1. Navigate to "Reports" → "Run New Scan"
2. Select scan type (Security, VM Attack, Nginx Attack)
3. Select target hosts
4. View results in Reports page

### Managing Users (Admin Only)
1. Navigate to "Users"
2. Change user roles between Admin and Viewer
3. View permission details

### Downloading Reports
1. Navigate to "Reports"
2. Click "PDF" button next to any completed scan
3. Report downloads as PDF with full details

## Security Scripts

All scripts are located in the project root:

- `vm-secure-setup.sh` - VM hardening automation
- `nginx-secure-setup.sh` - Nginx + ModSecurity WAF setup
- `security-scanner.sh` - Compliance scanning
- `attack-test/vm-attack-test.sh` - VM penetration testing
- `attack-test/nginx-attack-test.sh` - WAF validation testing

## Architecture

### Frontend
- Flask templates with modern dark UI
- Responsive design for all devices
- Real-time status updates

### Backend
- Flask web framework
- Supabase for authentication and database
- Row-level security (RLS) for data protection
- Background worker for async operations

### Database Schema
- `profiles` - User accounts and roles
- `hosts` - Managed server inventory
- `scan_reports` - Security scan results
- `setup_operations` - Hardening operation tracking

### Worker Process
- Processes pending operations asynchronously
- Executes remote scripts via SSH
- Updates database with results
- Handles errors gracefully

## Compliance Standards

### CIS Benchmarks
- SSH configuration (5.2.x)
- Firewall rules (4.4.x)
- System hardening (3.3.x)
- File integrity (6.1.x)

### NIST SP 800-53
- Access Control (AC-17, AC-7)
- System Protection (SC-5, SC-7, SC-8)
- System Integrity (SI-2, SI-3, SI-4, SI-7)

### PCI-DSS
- Network security (1.1-1.3, 4.1)
- Malware protection (5.1-5.2)
- Access control (8.1.6)
- Vulnerability management (6.2, 6.5-6.6)

### OWASP
- Top 10 web vulnerabilities
- API Security
- ModSecurity CRS coverage

### ISO 27001
- Cryptographic controls (A.10.1.1)
- Network security (A.13.1.x)
- Access control (A.9.x)

## Troubleshooting

### SSH Connection Issues
- Verify SSH key is installed on target host
- Check firewall allows SSH on configured port
- Ensure SSH user has sudo privileges

### Worker Not Processing
- Check worker.py is running
- Verify Supabase credentials in .env
- Check worker console for errors

### Scan Failures
- Verify target host is accessible
- Check script permissions on remote host
- Review scan output in report details

## Production Deployment

### Recommended Setup
- Use Gunicorn for Flask app
- Run worker as systemd service
- Configure proper firewall rules
- Use HTTPS with valid certificates
- Set strong SECRET_KEY
- Enable Supabase RLS policies

### Security Recommendations
- Rotate SSH keys regularly
- Review scan results weekly
- Monitor failed operations
- Keep dashboard dependencies updated
- Use dedicated service account for SSH

## License

This security dashboard is designed for defensive security operations only.

## Support

For issues or questions, refer to the Security Info page in the dashboard for detailed tool documentation
