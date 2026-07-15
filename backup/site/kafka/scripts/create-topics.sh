#!/bin/bash
# =============================================================================
# Kafka Topic Initialization
# =============================================================================
# Executed by the custom entrypoint after the broker becomes ready.
# Creates topics with consistent configuration:
#   - Partitions:       8
#   - Replication:      1 (single-node cluster)
#   - Compression:      snappy
#   - Retention:        7 days (168h) for ipdr-events, 30 days for security
#   - Cleanup policy:   delete
# =============================================================================

set -e

KAFKA_BOOTSTRAP_SERVER="localhost:9092"
REPLICATION="${KAFKA_REPLICATION_FACTOR:-1}"
PARTITIONS="${KAFKA_NUM_PARTITIONS:-8}"
KAFKA_TOPICS="/opt/kafka/bin/kafka-topics.sh"

echo "[init] Creating Kafka topics..."
echo "[init] Bootstrap server: ${KAFKA_BOOTSTRAP_SERVER}"
echo "[init] Default partitions: ${PARTITIONS}"
echo "[init] Replication factor: ${REPLICATION}"
echo ""

# ---------------------------------------------------------------------------
# ipdr-events — primary IPDR syslog event stream
# ---------------------------------------------------------------------------
echo "[init] Creating topic: ipdr-events"
${KAFKA_TOPICS} --bootstrap-server "${KAFKA_BOOTSTRAP_SERVER}" \
    --create --if-not-exists \
    --topic "ipdr-events" \
    --partitions "${KAFKA_IPDR_EVENTS_PARTITIONS:-${PARTITIONS}}" \
    --replication-factor "${REPLICATION}" \
    --config "retention.ms=604800000" \
    --config "retention.bytes=${KAFKA_IPDR_RETENTION_BYTES:-10737418240}" \
    --config "compression.type=snappy" \
    --config "cleanup.policy=delete" \
    --config "segment.bytes=${KAFKA_LOG_SEGMENT_BYTES:-536870912}" \
    --config "segment.ms=86400000" \
    --config "min.insync.replicas=${KAFKA_MIN_INSYNC_REPLICAS:-1}" \
    --config "max.message.bytes=${KAFKA_MESSAGE_MAX_BYTES:-10485760}"

# ---------------------------------------------------------------------------
# security-events
# ---------------------------------------------------------------------------
echo "[init] Creating topic: security-events"
${KAFKA_TOPICS} --bootstrap-server "${KAFKA_BOOTSTRAP_SERVER}" \
    --create --if-not-exists \
    --topic "security-events" \
    --partitions "${KAFKA_SECURITY_EVENTS_PARTITIONS:-${PARTITIONS}}" \
    --replication-factor "${REPLICATION}" \
    --config "retention.ms=${KAFKA_SECURITY_RETENTION_MS:-2592000000}" \
    --config "retention.bytes=${KAFKA_SECURITY_RETENTION_BYTES:-5368709120}" \
    --config "compression.type=snappy" \
    --config "cleanup.policy=delete" \
    --config "segment.bytes=268435456" \
    --config "segment.ms=86400000" \
    --config "min.insync.replicas=${KAFKA_MIN_INSYNC_REPLICAS:-1}" \
    --config "max.message.bytes=5242880"

# ---------------------------------------------------------------------------
# system-events
# ---------------------------------------------------------------------------
echo "[init] Creating topic: system-events"
${KAFKA_TOPICS} --bootstrap-server "${KAFKA_BOOTSTRAP_SERVER}" \
    --create --if-not-exists \
    --topic "system-events" \
    --partitions "${PARTITIONS}" \
    --replication-factor "${REPLICATION}" \
    --config "retention.ms=604800000" \
    --config "retention.bytes=1073741824" \
    --config "compression.type=snappy" \
    --config "cleanup.policy=delete" \
    --config "segment.bytes=268435456" \
    --config "segment.ms=86400000" \
    --config "min.insync.replicas=${KAFKA_MIN_INSYNC_REPLICAS:-1}" \
    --config "max.message.bytes=1048576"

# ---------------------------------------------------------------------------
# Verify
# ---------------------------------------------------------------------------
echo ""
echo "[init] Current topics:"
${KAFKA_TOPICS} --bootstrap-server "${KAFKA_BOOTSTRAP_SERVER}" --list

echo ""
echo "[init] Topic details:"
for topic in ipdr-events security-events system-events; do
    echo "──────────────────────────────────────────────"
    ${KAFKA_TOPICS} --bootstrap-server "${KAFKA_BOOTSTRAP_SERVER}" \
        --describe --topic "${topic}" 2>/dev/null || true
done

echo ""
echo "[init] Kafka topic initialization complete."
