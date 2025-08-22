```dockerfile
# syntax=docker/dockerfile:1.5

############################
# Stage 1: Frontend Build  #
############################
FROM node:20.11.1-alpine AS frontend-builder

# Set working directory for frontend
WORKDIR /app/frontend

# Install Yarn globally (Alpine node image may not have it)
RUN corepack enable && corepack prepare yarn@stable --activate

# Copy only dependency files first for layer caching
COPY frontend/package.json frontend/yarn.lock ./

# Install dependencies (production only)
RUN yarn install --frozen-lockfile --production

# Copy rest of frontend source
COPY frontend/ ./

# Build frontend for production
ENV NODE_ENV=production
RUN yarn build

############################
# Stage 2: Backend Build   #
############################
FROM python:3.11-slim AS backend-runtime

# Set working directory for backend
WORKDIR /app

# Install system dependencies for Python packages (e.g., pyodbc, duckdb, etc.)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        gcc \
        unixodbc-dev \
        libpq-dev \
        libmariadb-dev \
        libssl-dev \
        curl \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user for security
RUN useradd --create-home --shell /bin/bash appuser

# Copy Python dependency files first for layer caching
COPY backend/requirements.txt backend/pyproject.toml ./backend/

# Install Python dependencies (runtime only)
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r backend/requirements.txt

# Copy backend source code
COPY backend/ ./backend/

# Copy built frontend assets from previous stage to backend's static directory
COPY --from=frontend-builder /app/frontend/dist ./backend/py-src/data_formulator/dist

# Set environment variables (can be overridden at runtime)
ENV PYTHONUNBUFFERED=1 \
    FLASK_ENV=production \
    PORT=5000

# Expose Flask port
EXPOSE 5000

# Healthcheck for Flask server
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl --fail http://localhost:5000/health || exit 1

# Switch to non-root user
USER appuser

# Entrypoint: run the backend via CLI
CMD ["python", "-m", "data_formulator"]

# Metadata labels
LABEL maintainer="Your Name <your.email@example.com>"
LABEL org.opencontainers.image.source="https://github.com/your-org/data-formulator"
LABEL org.opencontainers.image.description="Production-ready Data Formulator full-stack app (React + Flask)"

```