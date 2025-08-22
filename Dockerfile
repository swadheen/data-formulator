# Stage 1: Build frontend
FROM node:20.11.1-alpine AS frontend-builder
WORKDIR /app
COPY package.json yarn.lock vite.config.ts tsconfig.json ./
COPY src/ ./src/
COPY public/ ./public/
RUN yarn install --frozen-lockfile --production=false
RUN yarn build

# Stage 2: Build backend and assemble final image
FROM python:3.11-slim AS backend-runtime
WORKDIR /app

# Install system dependencies for Python packages (if needed)
RUN apt-get update && \
    apt-get install -y --no-install-recommends build-essential gcc && \
    rm -rf /var/lib/apt/lists/*

# Copy backend source and dependency files
COPY pyproject.toml requirements.txt ./
COPY py-src/ ./py-src/

# Install Python dependencies
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt && \
    pip install --no-cache-dir .

# Remove build dependencies to reduce image size
RUN apt-get purge -y --auto-remove build-essential gcc

# Copy built frontend assets into backend's dist directory
COPY --from=frontend-builder /app/dist/ ./py-src/data_formulator/dist/

# Copy environment variable templates (not secrets)
COPY .env.template ./env.template
COPY api-keys.env.template ./api-keys.env.template

# Create non-root user and set permissions
RUN useradd --create-home --shell /bin/bash appuser && \
    chown -R appuser:appuser /app
USER appuser

# Expose Flask port
EXPOSE 5000

# Healthcheck for Flask API
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl --fail http://localhost:5000/api/health || exit 1

# Entrypoint
CMD ["python", "-m", "data_formulator"]