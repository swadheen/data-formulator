```dockerfile
# syntax=docker/dockerfile:1.5

############################
# Stage 1: Frontend Build  #
############################
FROM node:20-alpine AS frontend-builder

WORKDIR /app/frontend

# Copy only frontend sources and config for caching
COPY package.json yarn.lock ./
COPY src ./src
COPY public ./public
COPY tsconfig.json vite.config.* ./

# Install dependencies and build frontend
RUN yarn install --frozen-lockfile --production \
    && yarn build

############################
# Stage 2: Backend Build   #
############################
FROM python:3.11-slim AS backend-builder

WORKDIR /app

# Install system dependencies for Python packages (e.g., pyodbc, boto3, etc.)
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        gcc \
        unixodbc-dev \
        libpq-dev \
        curl \
    && rm -rf /var/lib/apt/lists/*

# Copy backend sources and dependency files
COPY pyproject.toml requirements.txt ./
COPY py-src ./py-src

# Copy built frontend assets from previous stage
COPY --from=frontend-builder /app/frontend/dist ./py-src/data_formulator/dist

# Install Python dependencies (prefer wheel, fallback to requirements.txt)
RUN pip install --upgrade pip \
    && pip install --no-cache-dir . \
    || pip install --no-cache-dir -r requirements.txt

############################
# Stage 3: Final Runtime   #
############################
FROM python:3.11-slim AS runtime

LABEL maintainer="Your Name <your@email.com>"
LABEL org.opencontainers.image.source="https://github.com/your/repo"
LABEL org.opencontainers.image.description="Production container for Data Formulator full-stack app"

# Create non-root user and group
RUN addgroup --system appuser && adduser --system --ingroup appuser appuser

WORKDIR /app

# Copy backend code and installed dependencies from backend-builder
COPY --from=backend-builder /app /app

# Set permissions for environment files (to be mounted at runtime)
RUN mkdir -p /app/config \
    && chown appuser:appuser /app/config

# Expose backend port
EXPOSE 5000

# Healthcheck for Flask server
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl --fail http://localhost:5000/api/health || exit 1

# Switch to non-root user
USER appuser

# Entrypoint: run the backend server via CLI
ENTRYPOINT ["data_formulator"]

# Optionally, allow override via CMD
CMD ["run-server"]

# Documentation: environment files should be mounted at /app/config/.env and /app/config/api-keys.env
```