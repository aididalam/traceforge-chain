#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ENV_FILE="${ROOT_DIR}/config/network.env"
COMPOSE_FILE="${ROOT_DIR}/docker/compose.yml"

GENESIS_FILE="${ROOT_DIR}/runtime/shared/genesis.json"
VALIDATOR1_PUBLIC_KEY="${ROOT_DIR}/runtime/validator1/data/key.pub"
BOOTNODES_FILE="${ROOT_DIR}/runtime/shared/bootnodes.txt"

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

PUBLIC_KEY="$(tr -d '[:space:]' < "${VALIDATOR1_PUBLIC_KEY}")"

PUBLIC_KEY="${PUBLIC_KEY#0x}"

if [[ ! "${PUBLIC_KEY}" =~ ^[0-9a-fA-F]{128}$ ]]; then
  echo "Error: validator1 public key has an unexpected format."
  exit 1
fi

BOOTNODE_ENODE="enode://${PUBLIC_KEY}@${VALIDATOR1_IP}:${P2P_PORT}"

printf '%s\n' "${BOOTNODE_ENODE}" > "${BOOTNODES_FILE}"

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

compose() {
  docker compose \
    --env-file "${ENV_FILE}" \
    -f "${COMPOSE_FILE}" \
    "$@"
}

echo "Starting validator1..."
compose up -d validator1

echo
echo "Waiting for validator1 RPC..."

ready=false

for attempt in $(seq 1 30); do

  if curl -fsS \
    -X POST \
    -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"web3_clientVersion","params":[],"id":1}' \
    "http://127.0.0.1:${RPC_PORT}" \
    >/dev/null 2>&1; then

    ready=true
    break
  fi

  sleep 1
done

if [[ "${ready}" != true ]]; then
  echo
  echo "Error: validator1 RPC did not become ready."
  echo
  echo "Check:"
  echo "  docker logs traceforge-validator1"
  exit 1
fi

echo "validator1 is ready."

echo
echo "Starting validator2, validator3, validator4..."

compose up -d validator2 validator3 validator4

echo
echo "TraceForge Chain started."
echo
compose ps
