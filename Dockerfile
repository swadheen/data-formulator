# syntax=docker/dockerfile:1.5

# Stage 1: Build frontend assets
FROM node:16-alpine AS frontend-builder

WORKDIR /app

# Copy frontend sources and dependency files for caching
COPY package.json yarn.lock ./
COPY vite.config.ts ./
COPY tsconfig.json ./
COPY src ./src
COPY public ./public

# Install dependencies and build
RUN yarn install --frozen-lockfile --production && \
    yarn build

# Stage 2: Build backend and final image
FROM python:3.11-slim AS backend-runtime

# Install system dependencies for Python packages (e.g., pyodbc, duckdb, databases)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        gcc \
        unixodbc-dev \
        libpq-dev \
        curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy backend code and dependency files
COPY py-src/data_formulator py-src/data_formulator
COPY requirements.txt requirements.txt
COPY pyproject.toml pyproject.toml
COPY MANIFEST.in MANIFEST.in

# Copy built frontend assets from frontend-builder stage
COPY --from=frontend-builder /app/py-src/data_formulator/dist py-src/data_formulator/dist

# Install Python dependencies
RUN pip install --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt && \
    pip install --no-cache-dir -e py-src/data_formulator && \
    rm -rf /root/.cache/pip

# Create non-root user and switch to it
RUN useradd --create-home --shell /bin/bash appuser
USER appuser

# Set environment variables
ENV PYTHONUNBUFFERED=1
ENV PORT=5000

EXPOSE 5000

# Healthcheck for Flask API
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl --fail http://localhost:5000/api/health || exit 1

WORKDIR /app/py-src/data_formulator

CMD ["python", "-m", "data_formulator"]