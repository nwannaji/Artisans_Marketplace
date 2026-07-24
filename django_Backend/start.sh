#!/bin/bash
# ── Render Start Script ──────────────────────────────
# Runs database migrations then starts daphne (ASGI server).
# Daphne serves both HTTP and WebSocket traffic.
# ─────────────────────────────────────────────────────

set -e

# Ensure logs directory exists (Django file handler needs it)
mkdir -p /app/logs

echo "=== Running database migrations ==="
python manage.py migrate --noinput

echo "=== Loading initial data (if fresh database) ==="
python manage.py loaddata fixtures/initial_data.json || echo "Data already loaded or fixture not found, skipping..."

echo "=== Creating superuser (if not exists) ==="
if [ -n "$ADMIN_USERNAME" ] && [ -n "$ADMIN_PASSWORD" ]; then
    python manage.py setup_admin --username "$ADMIN_USERNAME" --password "$ADMIN_PASSWORD" || true
else
    echo "Skipping admin creation: ADMIN_USERNAME and ADMIN_PASSWORD env vars not set"
fi

echo "=== Starting daphne on port ${PORT:-10000} ==="
exec daphne -b 0.0.0.0 -p ${PORT:-10000} artisans_backend.asgi:application