# syntax=docker/dockerfile:1.5

############################
# Frontend Build Stage
############################
FROM node:20.11.1-alpine AS frontend-builder

WORKDIR /app

# Copy only package.json and yarn.lock for dependency caching
COPY package.json yarn.lock ./

# Install dependencies
RUN yarn install --frozen-lockfile

# Copy all frontend source files (excluding py-src/)
COPY . ./

# Build frontend assets (output to py-src/data_formulator/dist)
RUN yarn build

############################
# Backend Build Stage
############################
FROM python:3.11-slim AS backend-runtime

# Install system dependencies for Python packages (duckdb, pyodbc, etc.)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        gcc \
        unixodbc-dev \
        libpq-dev \
        curl \
        && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd --create-home --shell /bin/bash appuser

# Set working directory to backend code
WORKDIR /app/py-src/data_formulator

# Copy backend source code
COPY py-src/data_formulator/ /app/py-src/data_formulator/

# Copy Python dependency files from root
COPY requirements.txt pyproject.toml /app/

# Install Python dependencies
RUN pip install --upgrade pip && \
    pip install --no-cache-dir -r /app/requirements.txt

# Copy built frontend assets from frontend-builder stage
COPY --from=frontend-builder /app/py-src/data_formulator/dist ./dist

# Set environment variables (do not include secrets)
ENV PYTHONUNBUFFERED=1 \
    FLASK_ENV=production

# Switch to non-root user
USER appuser

# Expose backend port
EXPOSE 5000

# Healthcheck for Flask API
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl --fail http://localhost:5000/api/health || exit 1

# Entrypoint: run backend via CLI
ENTRYPOINT ["python", "-m", "data_formulator"]