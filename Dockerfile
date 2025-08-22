# syntax=docker/dockerfile:1.5

# --- Stage 1: Frontend build ---
FROM node:20-alpine AS frontend-builder

WORKDIR /app/frontend

# Install only production dependencies and build assets
COPY frontend/package.json frontend/yarn.lock ./
RUN yarn install --frozen-lockfile --production

COPY frontend/ ./
RUN yarn build

# --- Stage 2: Backend build and runtime ---
FROM python:3.11-slim AS backend-runtime

LABEL maintainer="YourTeam <team@example.com>"
LABEL org.opencontainers.image.source="https://github.com/yourorg/yourrepo"
LABEL org.opencontainers.image.description="Production container for full-stack Flask + React app"

# Install system dependencies for Python packages (duckdb, pyodbc, etc.)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        gcc \
        libpq-dev \
        unixodbc-dev \
        curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy backend source and config files
COPY backend/ ./backend/
COPY pyproject.toml requirements.txt MANIFEST.in ./

# Copy built frontend assets from previous stage
COPY --from=frontend-builder /app/frontend/dist ./backend/py-src/data_formulator/dist

# Install Python dependencies
RUN pip install --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt && \
    pip install --no-cache-dir .

# Create non-root user and switch to it
RUN useradd --create-home --shell /bin/bash appuser
USER appuser

ENV PYTHONUNBUFFERED=1
ENV PORT=5000

EXPOSE 5000

# Healthcheck: ensure Flask server is up
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl --fail http://localhost:5000/api/health || exit 1

# Entrypoint: start Flask server
WORKDIR /app/backend
CMD ["python", "app.py"]

# --- Documentation ---
# Required environment variables (mount at runtime):
#   - .env (application config)
#   - api-keys.env (API keys for LLM providers)
#   - DB credentials (if using external DB)
#   - See README for details