# ── Build stage ──────────────────────────────────────────────
FROM python:3.12-slim AS builder

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Install build dependencies for psycopg2 and Pillow
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        gcc \
        libpq-dev \
        && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ── Runtime stage ───────────────────────────────────────────
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/install/bin:${PATH}" \
    PYTHONPATH="/install/lib/python3.12/site-packages:${PYTHONPATH}"

WORKDIR /app

# Install runtime dependencies (libpq for psycopg2, libjpeg for Pillow)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        libpq5 \
        libjpeg-dev \
        && rm -rf /var/lib/apt/lists/*

# Copy installed packages from builder
COPY --from=builder /install /install

# Copy project source
COPY . .

# Collect static files (WhiteNoise will serve them)
RUN DJANGO_SETTINGS_MODULE=artisans_backend.settings \
    SECRET_KEY=build-secret-key \
    DEBUG=False \
    python manage.py collectstatic --noinput 2>/dev/null || true

# Make start script executable
RUN chmod +x start.sh

# Render injects PORT env var; gunicorn must bind to it
EXPOSE 10000

# Non-root user for security
RUN useradd --create-home appuser && \
    chown -R appuser:appuser /app
USER appuser

# Start: run migrations first, then gunicorn
CMD ["./start.sh"]