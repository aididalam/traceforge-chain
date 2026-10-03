#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ENV_FILE="${ROOT_DIR}/config/network.env"
COMPOSE_FILE="${ROOT_DIR}/docker/compose.yml"

GENESIS_FILE="${ROOT_DIR}/runtime/shared/genesis.json"
VALIDATOR1_PUBLIC_KEY="${ROOT_DIR}/runtime/validator1/data/key.pub"
BOOTNODES_FILE="${ROOT_DIR}/runtime/shared/bootnodes.txt"

STARTUP_TIMEOUT_SECONDS="${STARTUP_TIMEOUT_SECONDS:-120}"
VALIDATOR_HEALTH_TIMEOUT_SECONDS="${VALIDATOR_HEALTH_TIMEOUT_SECONDS:-180}"
NETWORK_READY_TIMEOUT_SECONDS="${NETWORK_READY_TIMEOUT_SECONDS:-120}"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Error: ${ENV_FILE} not found."
  exit 1
fi

# shellcheck disable=SC1090
source "${ENV_FILE}"

if [[ ! -f "${GENESIS_FILE}" ]]; then
  echo "Error: runtime genesis not found."
  echo "Run ./scripts/prepare-runtime.sh first."
  exit 1
fi

if [[ ! -f "${VALIDATOR1_PUBLIC_KEY}" ]]; then
  echo "Error: validator1 public key not found."
  exit 1
fi

PUBLIC_KEY="$(
  tr -d '[:space:]' < "${VALIDATOR1_PUBLIC_KEY}"
)"

PUBLIC_KEY="${PUBLIC_KEY#0x}"

if [[ ! "${PUBLIC_KEY}" =~ ^[0-9a-fA-F]{128}$ ]]; then
  echo "Error: validator1 public key has an unexpected format."
  exit 1
fi

BOOTNODE_ENODE="enode://${PUBLIC_KEY}@${VALIDATOR1_IP}:${P2P_PORT}"

printf '%s\n' \
  "${BOOTNODE_ENODE}" \
  > "${BOOTNODES_FILE}"

compose() {
  docker compose \
    --env-file "${ENV_FILE}" \
    -f "${COMPOSE_FILE}" \
    "$@"
}

echo "TraceForge Chain"
echo "================"
echo
echo "Chain ID:       ${CHAIN_ID}"
echo "Validators:     ${VALIDATOR_COUNT}"
echo "RPC port:       ${RPC_PORT}"
echo "Docker network: ${DOCKER_NETWORK_NAME}"
echo
echo "Bootnode:"
echo "${BOOTNODE_ENODE}"
echo

echo "Starting validator1..."

compose up -d validator1

echo
echo "Waiting for validator1 RPC..."

rpc_ready=false

for ((elapsed=0; elapsed<STARTUP_TIMEOUT_SECONDS; elapsed++)); do

  if curl -fsS \
    --max-time 3 \
    -X POST \
    -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"web3_clientVersion","params":[],"id":1}' \
    "http://127.0.0.1:${RPC_PORT}" \
    >/dev/null 2>&1; then

    rpc_ready=true
    break
  fi

  sleep 1
done

if [[ "${rpc_ready}" != true ]]; then
  echo
  echo "Error: validator1 RPC did not become ready within ${STARTUP_TIMEOUT_SECONDS}s."
  echo
  echo "Check:"
  echo "  docker logs traceforge-validator1"
  exit 1
fi

echo "validator1 RPC is ready."

echo
echo "Starting remaining validators..."

compose up -d validator2 validator3 validator4

echo
echo "Waiting for validator containers to become healthy..."

deadline=$((SECONDS + VALIDATOR_HEALTH_TIMEOUT_SECONDS))

while true; do

  all_healthy=true

  for ((i=1; i<=VALIDATOR_COUNT; i++)); do

    container="traceforge-validator${i}"

    health="$(
      docker inspect \
        --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' \
        "${container}" \
        2>/dev/null || true
    )"

    if [[ "${health}" != "healthy" && "${health}" != "running" ]]; then
      all_healthy=false
      break
    fi
  done

  if [[ "${all_healthy}" == true ]]; then
    break
  fi

  if (( SECONDS >= deadline )); then
    echo
    echo "Error: validators did not become healthy within ${VALIDATOR_HEALTH_TIMEOUT_SECONDS}s."
    echo
    compose ps
    exit 1
  fi

  sleep 5
done

echo "All validator containers are healthy."

echo
echo "Waiting for QBFT network readiness..."

deadline=$((SECONDS + NETWORK_READY_TIMEOUT_SECONDS))

while true; do

  if "${ROOT_DIR}/scripts/health-check.sh" --quiet; then
    break
  fi

  if (( SECONDS >= deadline )); then
    echo
    echo "Error: TraceForge Chain did not become ready within ${NETWORK_READY_TIMEOUT_SECONDS}s."
    echo
    echo "Run:"
    echo "  ./scripts/health-check.sh"
    exit 1
  fi

  sleep 5
done

echo
echo "TraceForge Chain started successfully."
echo

"${ROOT_DIR}/scripts/health-check.sh"

echo
compose ps
