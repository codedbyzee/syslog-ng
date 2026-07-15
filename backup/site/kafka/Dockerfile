# =============================================================================
# Kafka — Custom Image (apache/kafka:3.9.0)
# =============================================================================
# Extends the official Apache Kafka image with:
#   - Custom entrypoint that runs init scripts after broker becomes ready
#   - Topic initialization scripts (ipdr-events, security-events, system-events)
#
# The official apache/kafka image runs as UID 1000 (appuser) and uses
# /etc/kafka/docker/run as entrypoint. This custom entrypoint wraps that
# to add init-script support (the official image lacks a built-in init.d
# mechanism).
# =============================================================================

FROM apache/kafka:3.9.0

USER root

# Create directories for init scripts and Kafka data
# The Apache Kafka official image runs as UID 1000 (appuser)
RUN mkdir -p /init-scripts /opt/kafka/data && chown -R 1000:1000 /init-scripts /opt/kafka/data

# Copy custom entrypoint and init scripts
COPY entrypoint.sh /opt/kafka/custom-entrypoint.sh
COPY scripts/ /init-scripts/

RUN chmod +x /opt/kafka/custom-entrypoint.sh && \
    chmod +x /init-scripts/*.sh

# Switch to the Apache image's default non-root user (UID 1000)
USER 1000

ENTRYPOINT ["/opt/kafka/custom-entrypoint.sh"]
