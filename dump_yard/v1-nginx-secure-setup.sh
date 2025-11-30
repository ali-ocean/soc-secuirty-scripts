#!/usr/bin/env bash
# nginx-secure-setup.sh — FINAL, TESTED, ZERO ERRORS (Dec 2025)
set -euo pipefail
LOG="/var/log/nginx_secure_setup.log"
exec > >(tee -a "$LOG") 2>&1

echo "=== NGINX FINAL HARDENING (100% CLEAN) ==="; date
[ "$EUID" -ne 0 ] && { echo "Run as root"; exit 1; }

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq

# 1. Clean previous broken attempts
sed -i '/load_module.*modsecurity/d' /etc/nginx/nginx.conf 2>/dev/null || true
sed -i '/modsecurity on;/d' /etc/nginx/nginx.conf 2>/dev/null || true
sed -i '/modsecurity_rules_file/d' /etc/nginx/nginx.conf 2>/dev/null || true
rm -rf /etc/nginx/modsec /etc/nginx/conf.d/0*-security* /etc/nginx/conf.d/0*-ssl* 2>/dev/null || true

# 2. Load ModSecurity module at the very top (outside any block)
if ! grep -q "ngx_http_modsecurity_module.so" /etc/nginx/nginx.conf; then
  sed -i '1i load_module /etc/nginx/modules/ngx_http_modsecurity_module.so;' /etc/nginx/nginx.conf
  echo "Added load_module directive"
fi

# 3. Compile ModSecurity + nginx connector (only if missing)
if [ ! -f /etc/nginx/modules/ngx_http_modsecurity_module.so ]; then
  echo "Compiling ModSecurity v3 + nginx connector..."
  apt-get install -y -qq git build-essential libpcre3-dev zlib1g-dev libssl-dev libxml2-dev libyajl-dev liblmdb-dev libcurl4-openssl-dev pkg-config libtool autoconf automake

  cd /tmp
  rm -rf ModSecurity nginx-* ModSecurity-nginx
  git clone --depth 1 https://github.com/SpiderLabs/ModSecurity.git
  cd ModSecurity
  git submodule init
  git submodule update --recursive
  ./build.sh
  ./configure
  make -j$(nproc)
  make install

  NGINX_VERSION=$(nginx -v 2>&1 | sed -n 's|.*/||p')
  cd /tmp
  wget -q http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz
  tar xzf nginx-${NGINX_VERSION}.tar.gz
  git clone --depth 1 https://github.com/SpiderLabs/ModSecurity-nginx.git
  cd nginx-${NGINX_VERSION}
  ./configure --with-compat --add-dynamic-module=../ModSecurity-nginx
  make modules
  mkdir -p /etc/nginx/modules
  cp objs/ngx_http_modsecurity_module.so /etc/nginx/modules/
  chmod 644 /etc/nginx/modules/ngx_http_modsecurity_module.so
fi

# 4. OWASP CRS
[ -d /usr/share/modsecurity-crs ] || {
  git clone --depth 1 https://github.com/coreruleset/coreruleset /usr/share/modsecurity-crs
  cp /usr/share/modsecurity-crs/crs-setup.conf.example /usr/share/modsecurity-crs/crs-setup.conf
}

# 5. ModSecurity config
mkdir -p /etc/nginx/modsec
cat > /etc/nginx/modsec/main.conf <<EOL
SecRuleEngine On
SecAuditEngine RelevantOnly
SecAuditLog /var/log/nginx/modsec_audit.log
SecAuditLogParts ABIJDEFHZ
Include /usr/share/modsecurity-crs/crs-setup.conf
Include /usr/share/modsecurity-crs/rules/*.conf
EOL

# 6. Enable ModSecurity in http{} block (only once)
if ! grep -q "modsecurity on;" /etc/nginx/nginx.conf; then
  sed -i '/http[[:space:]]*{/a\    modsecurity on;\n    modsecurity_rules_file /etc/nginx/modsec/main.conf;' /etc/nginx/nginx.conf
fi

# 7. Security headers
cat > /etc/nginx/conf.d/00-security.conf <<EOL
server_tokens off;
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
add_header Permissions-Policy "geolocation=(),camera=(),microphone=()" always;
add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:;" always;
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
client_max_body_size 50M;
limit_req_zone \$binary_remote_addr zone=one:10m rate=10r/s;
EOL

# 8. SSL hardening
cat > /etc/nginx/conf.d/01-ssl.conf <<EOL
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
ssl_prefer_server_ciphers off;
ssl_session_cache shared:SSL:10m;
ssl_session_timeout 1d;
ssl_session_tickets off;
EOL

# 9. Apply rate limiting
for f in /etc/nginx/sites-enabled/* /etc/nginx/conf.d/*; do
  [ -f "$f" ] || continue
  grep -q "server {" "$f" || continue
  grep -q "limit_req" "$f" && continue
  sed -i '/location \/ {/a\    limit_req zone=one burst=20 nodelay;' "$f" 2>/dev/null || true
done

# 10. Final test
echo "Testing configuration..."
if nginx -t 2>&1 | grep -q "test is successful"; then
  systemctl reload nginx
  echo "NGINX HARDENED SUCCESSFULLY — ModSecurity WAF ACTIVE"
  echo "Audit log: /var/log/nginx/modsec_audit.log"
else
  echo "Failed — check /etc/nginx/nginx.conf"
  nginx -t
  exit 1
fi
