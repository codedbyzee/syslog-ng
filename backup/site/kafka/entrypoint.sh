#!/bin/bash
# =============================================================================
# Kafka Custom Entrypoint — apache/kafka:3.9.0 with init script support
# =============================================================================
#
# The official apache/kafka:3.9.0 entrypoint (/etc/kafka/docker/run):
#   - Generates server.properties from KAFKA_* env vars
#   - Starts Kafka broker
# It does NOT auto-format KRaft storage — we must do that here.
#
# This custom entrypoint:
#   1. Formats KRaft storage on first boot only (checks meta.properties)
#   2. Starts Kafka via the official entrypoint in background
#   3. Waits for broker readiness via kafka-topics.sh
#   4. Executes init scripts (topic creation)
#   5. Brings Kafka to foreground for signal handling
#
# Environment variables:
#   KAFKA_KRAFT_CLUSTER_ID  — Required 22-char base64 UUID for KRaft
#   KAFKA_LOG_DIRS          — Data directory (default: /opt/kafka/data)
#   KAFKA_NODE_ID           — Node ID (default: 1)
#   All other KAFKA_* vars pass through to server.properties
# =============================================================================

set -e

INIT_SCRIPTS_DIR="/init-scripts"
KAFKA_DATA_DIR="${KAFKA_LOG_DIRS:-/opt/kafka/data}"

echo "[entrypoint] Starting IPDR Kafka broker (apache/kafka:3.9.0, KRaft mode)"

# ── Step 1: Ensure data directory exists ─────────────────────────────────────
echo "[entrypoint] Data directory: ${KAFKA_DATA_DIR}"
mkdir -p "${KAFKA_DATA_DIR}"

# ── Step 2: Format KRaft storage (first boot only) ───────────────────────────
# The official Apache Kafka image does NOT auto-format KRaft storage.
# kafka-storage.sh format initializes the metadata log partition.
# --ignore-formatted prevents re-formatting on subsequent restarts.
# We check for meta.properties to detect an already-initialized volume.
META_FILE="${KAFKA_DATA_DIR}/meta.properties"
if [ -f "${META_FILE}" ]; then
    echo "[entrypoint] KRaft metadata already exists at ${META_FILE}"
    echo "[entrypoint] Skipping storage format (data preserved)"
else
    if [ -z "${KAFKA_KRAFT_CLUSTER_ID}" ]; then
        # Auto-generate a unique cluster ID (base64-encoded 16 bytes = 22 chars)
        KAFKA_KRAFT_CLUSTER_ID="$(/opt/kafka/bin/kafka-storage.sh random-uuid)"
        echo "[entrypoint] Generated KAFKA_KRAFT_CLUSTER_ID=${KAFKA_KRAFT_CLUSTER_ID}"
    fi
    echo "[entrypoint] Formatting KRaft storage (first-time initialization)..."
    echo "[entrypoint] Cluster ID: ${KAFKA_KRAFT_CLUSTER_ID}"

    # Create minimal config for the format command
    # Must include all KRaft-required settings that the official entrypoint
    # would normally derive from KAFKA_* env vars at startup.
    FORMAT_CONFIG="/tmp/kraft-format.properties"
    cat > "${FORMAT_CONFIG}" << EOCONF
node.id=${KAFKA_NODE_ID:-1}
process.roles=${KAFKA_PROCESS_ROLES:-broker,controller}
controller.quorum.voters=${KAFKA_CONTROLLER_QUORUM_VOTERS:-1@kafka:9093}
controller.listener.names=${KAFKA_CONTROLLER_LISTENER_NAMES:-CONTROLLER}
listeners=${KAFKA_LISTENERS:-INTERNAL://:9092,CONTROLLER://:9093}
advertised.listeners=${KAFKA_ADVERTISED_LISTENERS:-INTERNAL://kafka:9092}
listener.security.protocol.map=${KAFKA_LISTENER_SECURITY_PROTOCOL_MAP:-INTERNAL:PLAINTEXT,CONTROLLER:PLAINTEXT}
inter.broker.listener.name=${KAFKA_INTER_BROKER_LISTENER_NAME:-INTERNAL}
EOCONF

    /opt/kafka/bin/kafka-storage.sh format \
        -t "${KAFKA_KRAFT_CLUSTER_ID}" \
        -c "${FORMAT_CONFIG}" \
        --ignore-formatted

    rm -f "${FORMAT_CONFIG}"
    echo "[entrypoint] KRaft storage formatted successfully"
fi

# ── Step 3: Start Kafka via the official entrypoint in background ────────────
echo "[entrypoint] Starting Kafka broker via official entrypoint..."
KAFKA_PID=0
/etc/kafka/docker/run &
KAFKA_PID=$!
echo "[entrypoint] Kafka PID: ${KAFKA_PID}"

# ── Step 4: Wait for broker to become ready ─────────────────────────────────
echo "[entrypoint] Waiting for Kafka broker to accept connections..."
MAX_RETRIES=45
RETRY_INTERVAL=2
READY=false

for ((i=1; i<=${MAX_RETRIES}; i++)); do
    if ! kill -0 ${KAFKA_PID} 2>/dev/null; then
        echo "[entrypoint] ERROR: Kafka process exited during startup!"
        wait ${KAFKA_PID} || true
        exit 1
    fi

    if /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list > /dev/null 2>&1; then
        READY=true
        echo "[entrypoint] Kafka broker is ready after ~$((i * RETRY_INTERVAL)) seconds"
        break
    fi

    if [ $((i % 5)) -eq 0 ]; then
        echo "[entrypoint] Still waiting for broker... (${i}/${MAX_RETRIES})"
    fi
    sleep ${RETRY_INTERVAL}
done

if [ "${READY}" != "true" ]; then
    echo "[entrypoint] ERROR: Kafka broker did not become ready within timeout"
    kill ${KAFKA_PID} 2>/dev/null || true
    exit 1
fi

# ── Step 5: Run init scripts ─────────────────────────────────────────────────
if [ -d "${INIT_SCRIPTS_DIR}" ]; then
    echo "[entrypoint] Running init scripts from ${INIT_SCRIPTS_DIR}..."
    for script in $(find "${INIT_SCRIPTS_DIR}" -maxdepth 1 -name '*.sh' -type f 2>/dev/null | sort); do
        echo "[entrypoint] Executing: ${script}"
        bash "${script}" || echo "[entrypoint] WARNING: ${script} exited with code $?"
    done
    echo "[entrypoint] All init scripts completed."
else
    echo "[entrypoint] No init scripts found at ${INIT_SCRIPTS_DIR}"
fi

# ── Step 6: Bring Kafka to foreground ────────────────────────────────────────
echo "[entrypoint] Kafka broker is running. Monitoring PID ${KAFKA_PID}..."
wait ${KAFKA_PID}
