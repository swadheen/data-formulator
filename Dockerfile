```dockerfile
# syntax=docker/dockerfile:1.5

############################
# Stage 1: Frontend Build  #
############################
FROM node:18-alpine AS frontend-builder

WORKDIR /app/frontend

# Install only production dependencies and build the frontend
COPY py-src/data_formulator/package.json py-src/data_formulator/yarn.lock ./
RUN yarn install --frozen-lockfile --production

COPY py-src/data_formulator/ ./
RUN yarn build

############################
# Stage 2: Backend Build   #
############################
FROM python:3.11-slim AS backend-builder

# Install system dependencies for Python connectors (ODBC, PostgreSQL, etc.)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        unixodbc \
        libpq-dev \
        curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy backend source and dependency files
COPY py-src/data_formulator/requirements.txt py-src/data_formulator/pyproject.toml ./
COPY py-src/data_formulator/ ./

# Install Python dependencies
RUN pip install --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

############################
# Stage 3: Final Runtime   #
############################
FROM python:3.11-slim

# Create a non-root user for security
RUN useradd --create-home --shell /bin/bash appuser

WORKDIR /app

# Install minimal system dependencies for runtime connectors
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        unixodbc \
        libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy Python dependencies from backend-builder
COPY --from=backend-builder /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY --from=backend-builder /usr/local/bin /usr/local/bin

# Copy backend source code
COPY --from=backend-builder /app /app

# Copy built frontend assets into backend static directory
COPY --from=frontend-builder /app/frontend/dist /app/dist

# Set environment variables (can be overridden at runtime)
ENV PYTHONUNBUFFERED=1 \
    FLASK_ENV=production \
    PORT=5000

# Expose backend port
EXPOSE 5000

# Set permissions and switch to non-root user
RUN chown -R appuser:appuser /app
USER appuser

# Healthcheck for Flask server
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:5000/health || exit 1

# Entrypoint: start Flask server
CMD ["python", "app.py"]

# Notes:
# - .env and api-keys.env should be mounted at runtime, not copied into the image.
# - For development, use a different Dockerfile or override CMD/ENV as needed.
```