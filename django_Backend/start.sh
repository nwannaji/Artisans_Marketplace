#!/bin/bash
# ── Render Start Script ──────────────────────────────
# Runs database migrations then starts gunicorn.
# This ensures tables are created/updated on every deploy.
# ─────────────────────────────────────────────────────

set -e

# Ensure logs directory exists (Django file handler needs it)
mkdir -p /app/logs

echo "=== Running database migrations ==="
python manage.py migrate --noinput

echo "=== Creating superuser (if not exists) ==="
python manage.py setup_admin || true

echo "=== Starting gunicorn on port ${PORT:-10000} ==="
exec gunicorn artisans_backend.wsgi:application \
     --bind 0.0.0.0:${PORT:-10000} \
     --workers 3 \
     --timeout 120