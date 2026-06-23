# Production Deployment: Nginx Reverse Proxy with TLS

## Context

The Django backend is currently running locally with `manage.py runserver` and the Flutter app points to a LAN IP (`http://172.16.2.158:8000`). For production, we need:
- A proper WSGI server (Gunicorn) instead of Django's dev server
- Nginx as a reverse proxy with TLS (HTTPS)
- A real domain name with DNS pointing to the server
- The Flutter app updated to use the production HTTPS URL

This plan covers a **Linux VPS deployment** (Ubuntu 22.04/24.04) — the most common and cost-effective option for a Nigerian marketplace. Steps for Docker and PaaS are noted as alternatives.

---

## Prerequisites You'll Need

1. **A VPS** — DigitalOcean ($6/mo), Hetzner (€4/mo), or Linode ($5/mo). Ubuntu 22.04 or 24.04 LTS.
2. **A domain name** — e.g., `fixit.com.ng` or `api.fixit.com.ng` (~₦2,000-5,000/year from WhoGoHost, DomainKing, or Namecheap).
3. **SSH access** to the VPS with a non-root user.

---

## Step 1: Server Setup

On the VPS, run:

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Python, PostgreSQL, Nginx, Certbot
sudo apt install -y python3-pip python3-venv python3-dev \
    libpq-dev postgresql postgresql-contrib \
    nginx certbot python3-certbot-nginx \
    git curl

# Create a deploy user (if not already)
sudo adduser deploy
sudo usermod -aG sudo deploy
```

---

## Step 2: PostgreSQL Database

```bash
# Create database and user
sudo -u postgres psql
CREATE DATABASE artisan_services_db;
CREATE USER artisan_user WITH PASSWORD 'your_secure_password';
ALTER ROLE artisan_user SET client_encoding TO 'utf8';
ALTER ROLE artisan_user SET default_transaction_isolation TO 'read committed';
ALTER ROLE artisan_user SET timezone TO 'Africa/Lagos';
GRANT ALL PRIVILEGES ON DATABASE artisan_services_db TO artisan_user;
\q
```

---

## Step 3: Django Application Setup

```bash
# Clone the repo and set up virtual environment
sudo mkdir -p /var/www/fixit
sudo chown deploy:deploy /var/www/fixit
cd /var/www/fixit
git clone <your-repo-url> .

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
cd django_Backend
pip install -r requirements.txt
pip install gunicorn whitenoise

# Create .env file (NEVER commit this)
cat > .env << 'EOF'
SECRET_KEY=your_generated_secret_key_here
DEBUG=False
ALLOWED_HOSTS=api.fixit.com.ng,fixit.com.ng,your-server-ip
DB_NAME=artisan_services_db
DB_USER=artisan_user
DB_PASSWORD=your_secure_password
DB_HOST=localhost
DB_PORT=5432

PAYSTACK_SECRET_KEY=sk_live_your_live_key
PAYSTACK_PUBLIC_KEY=pk_live_your_live_key
PAYSTACK_API_URL=https://api.paystack.co
PAYSTACK_CALLBACK_URL=https://api.fixit.com.ng/api/payments/callback/

CORS_ALLOWED_ORIGINS=https://fixit.com.ng,https://www.fixit.com.ng
EOF

# Create logs directory
mkdir -p logs
touch logs/.gitkeep

# Run migrations and collect static files
python manage.py migrate
python manage.py collectstatic --noinput

# Create admin user
python manage.py createsuperuser
```

---

## Step 4: Gunicorn Configuration

Create `/etc/systemd/system/fixit.service`:

```ini
[Unit]
Description=Fix-It Django Application
After=network.target

[Service]
User=deploy
Group=www-data
WorkingDirectory=/var/www/fixit/django_Backend
ExecStart=/var/www/fixit/django_Backend/venv/bin/gunicorn \
          --workers 3 \
          --bind unix:/var/www/fixit/django_Backend/fixit.sock \
          --timeout 120 \
          --access-logfile - \
          --error-logfile - \
          artisans_backend.wsgi:application
Environment="PATH=/var/www/fixit/django_Backend/venv/bin"
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl enable fixit
sudo systemctl start fixit
sudo systemctl status fixit
```

---

## Step 5: Nginx Configuration

Create `/etc/nginx/sites-available/fixit`:

```nginx
# Redirect HTTP to HTTPS
server {
    listen 80;
    server_name api.fixit.com.ng;
    return 301 https://$server_name$request_uri;
}

# HTTPS server
server {
    listen 443 ssl http2;
    server_name api.fixit.com.ng;

    # SSL certificates (will be configured by Certbot)
    ssl_certificate /etc/letsencrypt/live/api.fixit.com.ng/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.fixit.com.ng/privkey.pem;

    # SSL hardening
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    # Security headers
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy strict-origin-when-cross-origin always;

    # HSTS (Django also sets this, but belt-and-suspenders)
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;

    # Media files (profile pictures, chat audio, etc.)
    location /media/ {
        alias /var/www/fixit/django_Backend/media/;
        expires 7d;
        add_header Cache-Control "public, immutable";
    }

    # Static files (admin dashboard CSS/JS)
    location /static/ {
        alias /var/www/fixit/django_Backend/staticfiles/;
        expires 30d;
        add_header Cache-Control "public, immutable";
    }

    # Admin dashboard (Django templates + HTMX)
    location /dashboard/ {
        proxy_pass http://unix:/var/www/fixit/django_Backend/fixit.sock;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # API endpoints
    location / {
        proxy_pass http://unix:/var/www/fixit/django_Backend/fixit.sock;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Timeouts for long requests (file uploads, Paystack callbacks)
        proxy_connect_timeout 60s;
        proxy_read_timeout 120s;
        proxy_send_timeout 120s;

        # Allow large uploads (profile pictures)
        client_max_body_size 10M;
    }
}
```

```bash
# Enable the site
sudo ln -s /etc/nginx/sites-available/fixit /etc/nginx/sites-enabled/
sudo rm /etc/nginx/sites-enabled/default  # Remove default site

# Test configuration
sudo nginx -t

# Start Nginx
sudo systemctl restart nginx
```

---

## Step 6: TLS Certificate with Let's Encrypt

```bash
# Get a free TLS certificate (replace with your actual domain)
sudo certbot --nginx -d api.fixit.com.ng

# Certbot will automatically:
# 1. Verify domain ownership
# 2. Generate SSL certificates
# 3. Update Nginx config with cert paths
# 4. Set up auto-renewal via systemd timer

# Test auto-renewal
sudo certbot renew --dry-run
```

---

## Step 7: DNS Configuration

In your domain registrar (WhoGoHost, Namecheap, etc.):

1. Add an **A record**: `api.fixit.com.ng` → your VPS IP address
2. (Optional) Add a **CNAME**: `www.fixit.com.ng` → `api.fixit.com.ng`
3. Wait for DNS propagation (5-30 minutes)

---

## Step 8: Django Settings Updates

The settings.py changes are already in place from the production hardening work:

- ✅ `DEBUG = False` (env-controlled)
- ✅ `ALLOWED_HOSTS` from env var
- ✅ `CORS_ALLOWED_ORIGINS` from env var
- ✅ WhiteNoise middleware added
- ✅ `STATIC_ROOT` set for `collectstatic`
- ✅ Security headers for `DEBUG=False`
- ✅ `CONN_MAX_AGE = 60` for connection pooling
- ✅ `LOGGING` configured with file and console handlers
- ✅ `SESSION_COOKIE_AGE = 1800` (30 min)

**Additional setting needed** — Django must trust the `X-Forwarded-Proto` header from Nginx:

```python
# Already set in settings.py when DEBUG=False:
SECURE_PROXY_SSL_HEADER = ('HTTP_X_FORWARDED_PROTO', 'https')
```

This is already in the `if not DEBUG:` block. ✅

---

## Step 9: Update Flutter .env

Change the Flutter app's `.env` to point to the production URL:

```env
# Production
API_BASE_URL=https://api.fixit.com.ng

# Development (uncomment when testing locally)
# API_BASE_URL=http://10.0.2.2:8000
```

Also update the Android `network_security_config.xml` to allow the production domain:

```xml
<!-- Add your production domain -->
<domain includeSubdomains="true">api.fixit.com.ng</domain>
```

And remove the cleartext exceptions for local development (or keep them in a debug-only config).

---

## Step 10: Verify Everything Works

```bash
# On the server:
# 1. Check Gunicorn is running
sudo systemctl status fixit

# 2. Check Nginx is running
sudo systemctl status nginx

# 3. Test the API
curl -k https://api.fixit.com.ng/api/auth/login/ -X POST \
  -H "Content-Type: application/json" \
  -d '{"username":"test","password":"test","role":"CUSTOMER"}'

# 4. Check media file serving
# Upload a profile picture from the app, then verify it's accessible at:
# https://api.fixit.com.ng/media/profile_pics/<filename>

# 5. Check SSL rating
# Visit https://www.ssllabs.com/ssltest/ and test api.fixit.com.ng
```

---

## Files to Create/Modify

### On the server (not in git):

1. `/etc/systemd/system/fixit.service` — Gunicorn systemd service
2. `/etc/nginx/sites-available/fixit` — Nginx reverse proxy config
3. `/var/www/fixit/django_Backend/.env` — Production environment variables (never commit this)

### In the repo:

1. **`django_Backend/artisans_backend/settings.py`** — Already updated with WhiteNoise, STATIC_ROOT, CONN_MAX_AGE, LOGGING, session security. ✅
2. **`artisansApp/artisans_app/.env`** — Change `API_BASE_URL` to `https://api.fixit.com.ng`
3. **`artisansApp/artisans_app/android/app/src/main/res/xml/network_security_config.xml`** — Add production domain, remove local cleartext exceptions for release builds

### Production `.env` template (for server):

A `django_Backend/.env.production.example` file should be created as a reference.

---

## Costs Estimate

| Item | Cost (monthly) |
|------|---------------|
| VPS (1GB RAM) | $4-6 (~₦6,000-9,000) |
| Domain (.com.ng) | ~₦2,000/year |
| TLS Certificate | Free (Let's Encrypt) |
| **Total** | ~₦6,000-9,000/mo |

---

## Alternatives

### Docker Deployment
Instead of bare-metal Gunicorn, you can containerize with Docker. Requires:
- `Dockerfile` for the Django app
- `docker-compose.yml` with Nginx + Django + PostgreSQL containers
- Certbot running in a container
- More complex but more portable and reproducible

### Platform-as-a-Service (Render, Railway)
- Easiest option — push code, it deploys
- Built-in TLS, managed PostgreSQL, auto-scaling
- More expensive ($7-25/mo) but zero DevOps
- Limited control over Nginx configuration
- Good for getting started quickly

---

## Verification Checklist

- [ ] VPS provisioned and SSH accessible
- [ ] PostgreSQL database created
- [ ] Django app cloned and `.env` configured
- [ ] `python manage.py migrate` succeeds
- [ ] `python manage.py collectstatic` succeeds
- [ ] `python manage.py createsuperuser` works
- [ ] Gunicorn service running (`systemctl status fixit`)
- [ ] Nginx config tested (`nginx -t`)
- [ ] DNS A record pointing to VPS IP
- [ ] Let's Encrypt certificate installed
- [ ] `https://api.fixit.com.ng/admin/` loads (Django admin)
- [ ] `https://api.fixit.com.ng/api/auth/login/` returns 400 (correct — needs POST)
- [ ] Flutter app connects with `API_BASE_URL=https://api.fixit.com.ng`
- [ ] Profile picture upload works (media file accessible)
- [ ] SSL Labs test scores A or A+