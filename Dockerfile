# syntax=docker/dockerfile:1.5

############################
# Stage 1: Frontend Builder
############################
FROM node:20.10.0-alpine AS frontend-builder

WORKDIR /app

# Copy only frontend sources and dependency files
COPY package.json yarn.lock ./
COPY src/ ./src/
COPY public/ ./public/
COPY tsconfig.json ./
COPY vite.config.ts ./

# Install dependencies and build frontend
RUN yarn install --frozen-lockfile \
    && yarn build \
    && rm -rf node_modules

############################
# Stage 2: Backend Builder
############################
FROM python:3.11-slim AS backend-builder

WORKDIR /app

# Install system dependencies for pyodbc, duckdb, etc.
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    g++ \
    unixodbc-dev \
    libpq-dev \
    build-essential \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy backend sources and dependency files
COPY py-src/ /app/py-src/
COPY requirements.txt pyproject.toml ./

# Install Python dependencies
RUN pip install --upgrade pip setuptools wheel \
    && pip install --no-cache-dir -r requirements.txt \
    && pip install --no-cache-dir .

############################
# Stage 3: Final Runtime Image
############################
FROM python:3.11-slim

WORKDIR /app

# Install minimal system dependencies for runtime
RUN apt-get update && apt-get install -y --no-install-recommends \
    unixodbc \
    libpq5 \
    duckdb \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd --create-home --shell /bin/bash appuser

# Copy backend code and installed packages from backend-builder
COPY --from=backend-builder /app/py-src/ /app/py-src/
COPY --from=backend-builder /usr/local/lib/python3.11/site-packages/ /usr/local/lib/python3.11/site-packages/
COPY --from=backend-builder /usr/local/bin/ /usr/local/bin/

# Copy built frontend assets from frontend-builder
COPY --from=frontend-builder /app/py-src/data_formulator/dist/ /app/py-src/data_formulator/dist/

# Set permissions
RUN chown -R appuser:appuser /app

USER appuser

ENV PYTHONUNBUFFERED=1
ENV PORT=5000

EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl --fail http://localhost:5000/api/health || exit 1

# Entrypoint: run Flask backend
CMD ["python", "-m", "data_formulator"]