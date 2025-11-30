import os
import json
from datetime import datetime
from flask import Flask, render_template, request, redirect, url_for, flash, jsonify, send_file
from flask_login import LoginManager, UserMixin, login_user, logout_user, login_required, current_user
from functools import wraps
from supabase import create_client, Client
from dotenv import load_dotenv
import io
from xhtml2pdf import pisa

load_dotenv()

app = Flask(__name__)
app.config['SECRET_KEY'] = os.getenv('SECRET_KEY', os.urandom(24).hex())

supabase_url = os.getenv('VITE_SUPABASE_URL')
supabase_key = os.getenv('VITE_SUPABASE_SUPABASE_ANON_KEY')
supabase: Client = create_client(supabase_url, supabase_key)

login_manager = LoginManager()
login_manager.init_app(app)
login_manager.login_view = 'login'

class User(UserMixin):
    def __init__(self, id, email, full_name, role):
        self.id = id
        self.email = email
        self.full_name = full_name
        self.role = role

@login_manager.user_loader
def load_user(user_id):
    try:
        result = supabase.table('profiles').select('*').eq('id', user_id).maybeSingle().execute()
        if result.data:
            return User(
                id=result.data['id'],
                email=result.data['email'],
                full_name=result.data.get('full_name'),
                role=result.data['role']
            )
    except Exception as e:
        print(f"Error loading user: {e}")
    return None

def admin_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if not current_user.is_authenticated or current_user.role != 'admin':
            flash('Admin access required', 'error')
            return redirect(url_for('dashboard'))
        return f(*args, **kwargs)
    return decorated_function

@app.route('/')
def index():
    if current_user.is_authenticated:
        return redirect(url_for('dashboard'))
    return redirect(url_for('login'))

@app.route('/login', methods=['GET', 'POST'])
def login():
    if current_user.is_authenticated:
        return redirect(url_for('dashboard'))

    if request.method == 'POST':
        email = request.form.get('email')
        password = request.form.get('password')

        try:
            auth_response = supabase.auth.sign_in_with_password({
                "email": email,
                "password": password
            })

            if auth_response.user:
                profile = supabase.table('profiles').select('*').eq('id', auth_response.user.id).maybeSingle().execute()

                if profile.data:
                    user = User(
                        id=profile.data['id'],
                        email=profile.data['email'],
                        full_name=profile.data.get('full_name'),
                        role=profile.data['role']
                    )
                    login_user(user)
                    flash('Login successful!', 'success')
                    return redirect(url_for('dashboard'))
                else:
                    flash('Profile not found', 'error')
            else:
                flash('Invalid credentials', 'error')
        except Exception as e:
            flash(f'Login failed: {str(e)}', 'error')

    return render_template('login.html')

@app.route('/register', methods=['GET', 'POST'])
def register():
    if current_user.is_authenticated:
        return redirect(url_for('dashboard'))

    if request.method == 'POST':
        email = request.form.get('email')
        password = request.form.get('password')
        full_name = request.form.get('full_name')

        try:
            auth_response = supabase.auth.sign_up({
                "email": email,
                "password": password
            })

            if auth_response.user:
                supabase.table('profiles').insert({
                    "id": auth_response.user.id,
                    "email": email,
                    "full_name": full_name,
                    "role": "viewer"
                }).execute()

                flash('Registration successful! Please login.', 'success')
                return redirect(url_for('login'))
        except Exception as e:
            flash(f'Registration failed: {str(e)}', 'error')

    return render_template('register.html')

@app.route('/logout')
@login_required
def logout():
    supabase.auth.sign_out()
    logout_user()
    flash('Logged out successfully', 'success')
    return redirect(url_for('login'))

@app.route('/dashboard')
@login_required
def dashboard():
    try:
        hosts = supabase.table('hosts').select('*').execute()
        recent_scans = supabase.table('scan_reports').select('*, hosts(hostname)').order('created_at', desc=True).limit(10).execute()

        stats = {
            'total_hosts': len(hosts.data) if hosts.data else 0,
            'active_hosts': sum(1 for h in (hosts.data or []) if h['status'] == 'active'),
            'total_scans': 0,
            'failed_scans': 0
        }

        all_scans = supabase.table('scan_reports').select('status').execute()
        if all_scans.data:
            stats['total_scans'] = len(all_scans.data)
            stats['failed_scans'] = sum(1 for s in all_scans.data if s['status'] == 'failed')

        return render_template('dashboard.html', stats=stats, recent_scans=recent_scans.data or [])
    except Exception as e:
        flash(f'Error loading dashboard: {str(e)}', 'error')
        return render_template('dashboard.html', stats={}, recent_scans=[])

@app.route('/hosts')
@login_required
def hosts():
    try:
        hosts_data = supabase.table('hosts').select('*').order('created_at', desc=True).execute()
        return render_template('hosts.html', hosts=hosts_data.data or [])
    except Exception as e:
        flash(f'Error loading hosts: {str(e)}', 'error')
        return render_template('hosts.html', hosts=[])

@app.route('/hosts/add', methods=['GET', 'POST'])
@login_required
@admin_required
def add_host():
    if request.method == 'POST':
        try:
            supabase.table('hosts').insert({
                'hostname': request.form.get('hostname'),
                'ip_address': request.form.get('ip_address'),
                'ssh_port': int(request.form.get('ssh_port', 9977)),
                'ssh_user': request.form.get('ssh_user', 'root'),
                'description': request.form.get('description'),
                'status': 'active',
                'created_by': current_user.id
            }).execute()
            flash('Host added successfully!', 'success')
            return redirect(url_for('hosts'))
        except Exception as e:
            flash(f'Error adding host: {str(e)}', 'error')

    return render_template('add_host.html')

@app.route('/hosts/<host_id>/edit', methods=['GET', 'POST'])
@login_required
@admin_required
def edit_host(host_id):
    if request.method == 'POST':
        try:
            supabase.table('hosts').update({
                'hostname': request.form.get('hostname'),
                'ip_address': request.form.get('ip_address'),
                'ssh_port': int(request.form.get('ssh_port', 9977)),
                'ssh_user': request.form.get('ssh_user', 'root'),
                'description': request.form.get('description'),
                'status': request.form.get('status'),
                'updated_at': datetime.utcnow().isoformat()
            }).eq('id', host_id).execute()
            flash('Host updated successfully!', 'success')
            return redirect(url_for('hosts'))
        except Exception as e:
            flash(f'Error updating host: {str(e)}', 'error')

    try:
        host = supabase.table('hosts').select('*').eq('id', host_id).maybeSingle().execute()
        return render_template('edit_host.html', host=host.data)
    except Exception as e:
        flash(f'Error loading host: {str(e)}', 'error')
        return redirect(url_for('hosts'))

@app.route('/hosts/<host_id>/delete', methods=['POST'])
@login_required
@admin_required
def delete_host(host_id):
    try:
        supabase.table('hosts').delete().eq('id', host_id).execute()
        flash('Host deleted successfully!', 'success')
    except Exception as e:
        flash(f'Error deleting host: {str(e)}', 'error')
    return redirect(url_for('hosts'))

@app.route('/reports')
@login_required
def reports():
    search = request.args.get('search', '')
    scan_type = request.args.get('scan_type', '')
    status = request.args.get('status', '')

    try:
        query = supabase.table('scan_reports').select('*, hosts(hostname, ip_address)').order('created_at', desc=True)

        if search:
            query = query.ilike('hosts.hostname', f'%{search}%')
        if scan_type:
            query = query.eq('scan_type', scan_type)
        if status:
            query = query.eq('status', status)

        reports_data = query.execute()
        return render_template('reports.html', reports=reports_data.data or [], search=search, scan_type=scan_type, status=status)
    except Exception as e:
        flash(f'Error loading reports: {str(e)}', 'error')
        return render_template('reports.html', reports=[], search='', scan_type='', status='')

@app.route('/reports/<report_id>')
@login_required
def view_report(report_id):
    try:
        report = supabase.table('scan_reports').select('*, hosts(hostname, ip_address)').eq('id', report_id).maybeSingle().execute()
        return render_template('view_report.html', report=report.data)
    except Exception as e:
        flash(f'Error loading report: {str(e)}', 'error')
        return redirect(url_for('reports'))

@app.route('/reports/<report_id>/download')
@login_required
def download_report(report_id):
    try:
        report = supabase.table('scan_reports').select('*, hosts(hostname, ip_address)').eq('id', report_id).maybeSingle().execute()

        if not report.data or not report.data.get('html_report'):
            flash('Report not found or incomplete', 'error')
            return redirect(url_for('reports'))

        pdf_buffer = io.BytesIO()
        pisa.CreatePDF(io.BytesIO(report.data['html_report'].encode('utf-8')), dest=pdf_buffer)
        pdf_buffer.seek(0)

        filename = f"security_report_{report.data['hosts']['hostname']}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.pdf"
        return send_file(pdf_buffer, as_attachment=True, download_name=filename, mimetype='application/pdf')
    except Exception as e:
        flash(f'Error downloading report: {str(e)}', 'error')
        return redirect(url_for('reports'))

@app.route('/operations')
@login_required
@admin_required
def operations():
    try:
        ops_data = supabase.table('setup_operations').select('*, hosts(hostname, ip_address)').order('created_at', desc=True).execute()
        return render_template('operations.html', operations=ops_data.data or [])
    except Exception as e:
        flash(f'Error loading operations: {str(e)}', 'error')
        return render_template('operations.html', operations=[])

@app.route('/operations/setup', methods=['GET', 'POST'])
@login_required
@admin_required
def setup_operation():
    if request.method == 'POST':
        try:
            host_ids = request.form.getlist('host_ids')
            operation_type = request.form.get('operation_type')

            for host_id in host_ids:
                supabase.table('setup_operations').insert({
                    'host_id': host_id,
                    'operation_type': operation_type,
                    'status': 'pending',
                    'created_by': current_user.id
                }).execute()

            flash(f'Setup operation queued for {len(host_ids)} host(s)', 'success')
            return redirect(url_for('operations'))
        except Exception as e:
            flash(f'Error creating operation: {str(e)}', 'error')

    try:
        hosts_data = supabase.table('hosts').select('*').eq('status', 'active').execute()
        return render_template('setup_operation.html', hosts=hosts_data.data or [])
    except Exception as e:
        flash(f'Error loading hosts: {str(e)}', 'error')
        return render_template('setup_operation.html', hosts=[])

@app.route('/scans/run', methods=['GET', 'POST'])
@login_required
@admin_required
def run_scan():
    if request.method == 'POST':
        try:
            host_ids = request.form.getlist('host_ids')
            scan_type = request.form.get('scan_type')

            for host_id in host_ids:
                supabase.table('scan_reports').insert({
                    'host_id': host_id,
                    'scan_type': scan_type,
                    'status': 'pending',
                    'created_by': current_user.id
                }).execute()

            flash(f'Scan queued for {len(host_ids)} host(s)', 'success')
            return redirect(url_for('reports'))
        except Exception as e:
            flash(f'Error creating scan: {str(e)}', 'error')

    try:
        hosts_data = supabase.table('hosts').select('*').eq('status', 'active').execute()
        return render_template('run_scan.html', hosts=hosts_data.data or [])
    except Exception as e:
        flash(f'Error loading hosts: {str(e)}', 'error')
        return render_template('run_scan.html', hosts=[])

@app.route('/users')
@login_required
@admin_required
def users():
    try:
        users_data = supabase.table('profiles').select('*').order('created_at', desc=True).execute()
        return render_template('users.html', users=users_data.data or [])
    except Exception as e:
        flash(f'Error loading users: {str(e)}', 'error')
        return render_template('users.html', users=[])

@app.route('/users/<user_id>/role', methods=['POST'])
@login_required
@admin_required
def update_user_role(user_id):
    try:
        new_role = request.form.get('role')
        if new_role not in ['admin', 'viewer']:
            flash('Invalid role', 'error')
            return redirect(url_for('users'))

        supabase.table('profiles').update({
            'role': new_role,
            'updated_at': datetime.utcnow().isoformat()
        }).eq('id', user_id).execute()

        flash('User role updated successfully!', 'success')
    except Exception as e:
        flash(f'Error updating role: {str(e)}', 'error')
    return redirect(url_for('users'))

@app.route('/info')
@login_required
def security_info():
    return render_template('security_info.html')

@app.route('/profile')
@login_required
def profile():
    return render_template('profile.html')

@app.route('/profile/update', methods=['POST'])
@login_required
def update_profile():
    try:
        supabase.table('profiles').update({
            'full_name': request.form.get('full_name'),
            'updated_at': datetime.utcnow().isoformat()
        }).eq('id', current_user.id).execute()
        flash('Profile updated successfully!', 'success')
    except Exception as e:
        flash(f'Error updating profile: {str(e)}', 'error')
    return redirect(url_for('profile'))

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
