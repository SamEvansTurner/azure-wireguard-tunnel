FROM alpine:3.19

# Install required packages
RUN apk add --no-cache \
    openssh-client \
    openssl \
    bash \
    ca-certificates

# Create working directory
WORKDIR /app

# Copy scripts
COPY sync-certs.sh /app/
COPY entrypoint.sh /app/

# Make scripts executable
RUN chmod +x /app/*.sh

# Create directories
RUN mkdir -p /certs

# Run as root for maximum compatibility
# Container isolation and read-only volumes provide security
USER root

# Set entrypoint
ENTRYPOINT ["/app/entrypoint.sh"]
