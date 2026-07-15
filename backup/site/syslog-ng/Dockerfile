# =============================================================================
# syslog-ng — IPDR Syslog Collector & Kafka Forwarder
# =============================================================================
# Based on linuxserver/syslog-ng (Alpine-based).
# Configuration is loaded from /config/syslog-ng.conf.
# The LinuxServer s6-overlay handles startup — no custom entrypoint needed.
#
# Pipeline:
#   Network devices (UDP/TCP/TLS 514) → syslog-ng → Kafka topic ipdr-events
# =============================================================================

FROM lscr.io/linuxserver/syslog-ng:4.10.2

# Copy IPDR syslog-ng configuration
COPY config/syslog-ng.conf /config/syslog-ng.conf

# Create directories for fallback logs and disk buffer
RUN mkdir -p /config/log /config/tls

# LinuxServer s6-overlay manages the syslog-ng process automatically.
# No custom entrypoint override is needed.

EXPOSE 514/udp 514/tcp 6514/tcp
