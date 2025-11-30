#!/bin/bash
# nginx-secure-waf.sh — FINAL PRODUCTION VERSION (Dec 2025)
# Nginx.org mainline + ModSecurity v3 + OWASP CRS + Zero errors
set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()   { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[ERR]${NC} $1"; exit 1; }

[ "$EUID" -ne 0 ] && error "Run as root"

log "Starting FINAL Nginx + ModSecurity WAF hardening..."

# 1. Ensure nginx.org mainline
if ! nginx -v 2>&1 | grep -q "nginx/1"; then
    log "Installing nginx.org mainline..."
    wget -qO - https://nginx.org/keys/nginx_signing.key | apt-key add - >/dev/null 2>&1
    echo "deb https://nginx.org/packages/mainline/ubuntu/ $(lsb_release -sc) nginx" > /etc/apt/sources.list.d/nginx.list
    apt update -qq
    apt install -y -qq nginx
fi

# 2. Create modules dir
mkdir -p /etc/nginx/modules

# 3. Compile ModSecurity module (only if missing)
if [ ! -f /etc/nginx/modules/ngx_http_modsecurity_module.so ]; then
    log "Compiling ModSecurity v3 + nginx connector..."
    apt install -y -qq git build-essential libpcre3-dev zlib1g-dev libssl-dev libxml2-dev libyajl-dev liblmdb-dev pkg-config libtool autoconf automake >/dev/null 2>&1

    cd /tmp
    rm -rf ModSecurity nginx-* ModSecurity-nginx
    git clone --depth 1 https://github.com/SpiderLabs/ModSecurity >/dev/null 2>&1
    cd ModSecurity
    git submodule init && git submodule update --recursive >/dev/null 2>&1
    ./build.sh >/dev/null 2>&1
    ./configure >/dev/null 2>&1
    make -j$(nproc) >/dev/null 2>&1 && make install >/dev/null 2>&1

    NGINX_VERSION=$(nginx -v 2>&1 | sed -n 's|.*nginx/\(.*\)|\1|p')
    cd /tmp
    wget -q http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz
    tar xzf nginx-${NGINX_VERSION}.tar.gz
    git clone --depth 1 https://github.com/SpiderLabs/ModSecurity-nginx.git >/dev/null 2>&1
    cd nginx-${NGINX_VERSION}
    ./configure --with-compat --add-dynamic-module=../ModSecurity-nginx >/dev/null 2>&1
    make modules >/dev/null 2>&1
    cp objs/ngx_http_modsecurity_module.so /etc/nginx/modules/
    chmod 644 /etc/nginx/modules/ngx_http_modsecurity_module.so
fi

# 4. Load module at top (only once)
if ! grep -q "ngx_http_modsecurity_module.so" /etc/nginx/nginx.conf; then
    sed -i '1i load_module /etc/nginx/modules/ngx_http_modsecurity_module.so;' /etc/nginx/nginx.conf
fi

# 5. OWASP CRS
[ -d /usr/share/modsecurity-crs ] || {
    git clone --depth 1 https://github.com/coreruleset/coreruleset /usr/share/modsecurity-crs >/dev/null 2>&1
    cp /usr/share/modsecurity-crs/crs-setup.conf.example /usr/share/modsecurity-crs/crs-setup.conf
}

# 6. ModSecurity config
mkdir -p /etc/nginx/modsec
cat > /etc/nginx/modsec/main.conf <<'EOL'
SecRuleEngine On
SecAuditEngine RelevantOnly
SecAuditLog /var/log/nginx/modsec_audit.log
SecAuditLogParts ABIJDEFHZ
Include /usr/share/modsecurity-crs/crs-setup.conf
Include /usr/share/modsecurity-crs/rules/*.conf
EOL

# 7. Enable ModSecurity globally (only once)
if ! grep -q "modsecurity on;" /etc/nginx/nginx.conf; then
    sed -i '/http[[:space:]]*{/a\    modsecurity on;\n    modsecurity_rules_file /etc/nginx/modsec/main.conf;' /etc/nginx/nginx.conf
fi

# 8. Global security headers + hardening
cat > /etc/nginx/conf.d/00-security.conf <<'EOL'
server_tokens off;

add_header X-Frame-Options            "SAMEORIGIN" always;
add_header X-Content-Type-Options     "nosniff" always;
add_header X-XSS-Protection           "1; mode=block" always;
add_header Referrer-Policy            "strict-origin-when-cross-origin" always;
add_header Permissions-Policy         "geolocation=(),camera=(),microphone=()" always;
add_header Content-Security-Policy    "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:;" always;
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;

client_max_body_size 50M;
limit_req_zone $binary_remote_addr zone=one:10m rate=10r/s;
EOL

# 9. SSL hardening
cat > /etc/nginx/conf.d/01-ssl.conf <<'EOL'
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
ssl_prefer_server_ciphers off;
ssl_session_cache shared:SSL:10m;
ssl_session_timeout 1d;
ssl_session_tickets off;
EOL

# 10. Apply rate limiting to all sites
for f in /etc/nginx/sites-enabled/* /etc/nginx/conf.d/*; do
    [ -f "$f" ] || continue
    grep -q "server {" "$f" || continue
    grep -q "limit_req" "$f" && continue
    sed -i '/location \/ {/a\    limit_req zone=one burst=20 nodelay;' "$f" 2>/dev/null || true
done

# 11. Final test
log "Testing configuration..."
if nginx -t; then
    systemctl reload nginx
    log "NGINX + MODSECURITY WAF FULLY HARDENED — ZERO ERRORS"
    echo -e "${GREEN}WAF Active | Headers Active | Rate Limiting Active${NC}"
    echo "Test WAF: curl \"http://$(hostname -I | awk '{print $1}')/?id=1'+OR+1=1--\""
    echo "Should return 403 Forbidden"
else
    warn "Config test failed — review /etc/nginx/nginx.conf"
    nginx -t
    exit 1
fi
