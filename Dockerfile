# ----------- Frontend Build Stage -----------
FROM node:20.11.1-alpine AS frontend-builder

WORKDIR /app

# Copy only dependency files first for caching
COPY py-src/data_formulator/package.json py-src/data_formulator/yarn.lock ./

RUN yarn install --frozen-lockfile

# Copy the rest of the frontend source
COPY py-src/data_formulator/ ./

# Build the frontend assets
RUN yarn build

# ----------- Backend/Runtime Stage -----------
FROM python:3.11-slim AS backend-runtime

# Install system dependencies required for Python packages
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        gcc \
        libpq-dev \
        libffi-dev \
        libssl-dev \
        curl \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy Python dependency files first for caching
COPY py-src/requirements.txt py-src/pyproject.toml ./py-src/

# Install Python dependencies
RUN pip install --upgrade pip && \
    pip install --no-cache-dir setuptools && \
    pip install --no-cache-dir -r ./py-src/requirements.txt

# Copy backend source code
COPY py-src/ ./py-src/

# Copy built frontend assets from frontend-builder stage
COPY --from=frontend-builder /app/dist ./py-src/data_formulator/dist

# Create a non-root user and switch to it
RUN useradd --create-home --shell /bin/bash appuser
USER appuser

# Set environment variables (can be overridden at runtime)
ENV PYTHONUNBUFFERED=1
ENV PORT=5000

# Expose Flask port
EXPOSE 5000

# Healthcheck for Flask server
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl --fail http://localhost:5000/health || exit 1

# Entrypoint: run the Flask app via the Python package
CMD ["python", "-m", "data_formulator"]