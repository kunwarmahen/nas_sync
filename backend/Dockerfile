# Build stage
FROM python:3.11-slim as builder

WORKDIR /app

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --user --no-cache-dir -r requirements.txt

# Runtime stage
FROM python:3.11-slim

WORKDIR /app

# Install runtime dependencies including tzdata for timezone support
RUN apt-get update && apt-get install -y --no-install-recommends \
    rsync \
    curl \
    tzdata \
    && rm -rf /var/lib/apt/lists/*

# Copy Python dependencies from builder
COPY --from=builder /root/.local /root/.local

# Copy application files
COPY usb_sync_backend.py .
COPY entrypoint.sh .

# Make scripts executable
RUN chmod +x entrypoint.sh

# Set environment variables
ENV PATH=/root/.local/bin:$PATH \
    PYTHONUNBUFFERED=1 \
    FLASK_APP=usb_sync_backend.py \
    TZ=UTC

# Create directories
RUN mkdir -p /etc/usb-sync-manager/logs /backups

# Expose port
EXPOSE 5000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:5000/health || exit 1

# Run application
ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["python", "usb_sync_backend.py"]