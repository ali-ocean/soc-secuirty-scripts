#!/usr/bin/env python3
import os
import sys

print("=== Security Dashboard Installation Verification ===\n")

errors = []
warnings = []
success = []

print("[1/5] Checking project files...")
required_files = [
    'app.py',
    'worker.py',
    'requirements.txt',
    '.env',
    'templates/base.html',
    'templates/login.html',
    'static/css/style.css',
    'vm-secure-setup.sh',
    'nginx-secure-setup.sh',
    'security-scanner.sh'
]

for file in required_files:
    if os.path.exists(file):
        success.append(f"✓ Found {file}")
    else:
        errors.append(f"✗ Missing {file}")

print("[2/5] Checking Python dependencies...")
try:
    import flask
    success.append("✓ Flask installed")
except ImportError:
    errors.append("✗ Flask not installed (pip install Flask)")

try:
    import flask_login
    success.append("✓ Flask-Login installed")
except ImportError:
    errors.append("✗ Flask-Login not installed")

try:
    import supabase
    success.append("✓ Supabase client installed")
except ImportError:
    errors.append("✗ Supabase not installed")

try:
    import paramiko
    success.append("✓ Paramiko (SSH) installed")
except ImportError:
    warnings.append("⚠ Paramiko not installed (needed for remote execution)")

print("[3/5] Checking environment configuration...")
if os.path.exists('.env'):
    with open('.env', 'r') as f:
        env_content = f.read()
        if 'VITE_SUPABASE_URL' in env_content:
            success.append("✓ Supabase URL configured")
        else:
            errors.append("✗ Missing VITE_SUPABASE_URL in .env")

        if 'VITE_SUPABASE_SUPABASE_ANON_KEY' in env_content:
            success.append("✓ Supabase key configured")
        else:
            errors.append("✗ Missing VITE_SUPABASE_SUPABASE_ANON_KEY in .env")
else:
    errors.append("✗ .env file not found")

print("[4/5] Checking security scripts...")
scripts = ['vm-secure-setup.sh', 'nginx-secure-setup.sh', 'security-scanner.sh']
for script in scripts:
    if os.path.exists(script):
        if os.access(script, os.X_OK):
            success.append(f"✓ {script} is executable")
        else:
            warnings.append(f"⚠ {script} not executable (chmod +x {script})")
    else:
        errors.append(f"✗ {script} not found")

print("[5/5] Checking database connection...")
try:
    from supabase import create_client
    from dotenv import load_dotenv
    load_dotenv()

    url = os.getenv('VITE_SUPABASE_URL')
    key = os.getenv('VITE_SUPABASE_SUPABASE_ANON_KEY')

    if url and key:
        client = create_client(url, key)
        success.append("✓ Supabase connection configured")
    else:
        errors.append("✗ Cannot load Supabase credentials")
except Exception as e:
    errors.append(f"✗ Database connection error: {str(e)}")

print("\n" + "="*60)
print("VERIFICATION RESULTS")
print("="*60 + "\n")

if success:
    print(f"SUCCESS ({len(success)}):")
    for msg in success[:10]:
        print(f"  {msg}")
    if len(success) > 10:
        print(f"  ... and {len(success)-10} more\n")
    else:
        print()

if warnings:
    print(f"WARNINGS ({len(warnings)}):")
    for msg in warnings:
        print(f"  {msg}")
    print()

if errors:
    print(f"ERRORS ({len(errors)}):")
    for msg in errors:
        print(f"  {msg}")
    print()

print("="*60)

if not errors:
    print("✓ Installation verified successfully!")
    print("\nNext steps:")
    print("  1. Start Flask app:    python3 app.py")
    print("  2. Start worker:       python3 worker.py")
    print("  3. Open browser:       http://localhost:5000")
    print("  4. Register first user")
    print("  5. Promote to admin via Supabase dashboard")
    sys.exit(0)
else:
    print("✗ Installation has errors - please fix before proceeding")
    print("\nInstall missing dependencies:")
    print("  pip install -r requirements.txt")
    sys.exit(1)
