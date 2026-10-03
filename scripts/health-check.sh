#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/config/network.env"

QUIET=false
if [[ "${1:-}" == "--quiet" ]]; then
  QUIET=true
fi

ok() {
  if [[ "${QUIET}" == false ]]; then
    echo "[OK] $*"
  fi
}

fail() {
  if [[ "${QUIET}" == false ]]; then
    echo "[FAIL] $*" >&2
  fi
  exit 1
}

if [[ ! -f "${ENV_FILE}" ]]; then
  fail "${ENV_FILE} not found"
fi

# shellcheck disable=SC1090
source "${ENV_FILE}"

RPC_URL="http://127.0.0.1:${RPC_PORT}"

rpc() {
  local method="$1"
  local params="$2"

  curl -fsS \
    --max-time 5 \
    -X POST \
    -H "Content-Type: application/json" \
    --data "{\"jsonrpc\":\"2.0\",\"method\":\"${method}\",\"params\":${params},\"id\":1}" \
    "${RPC_URL}"
}

extract_string_result() {
  sed -n \
    's/.*"result"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
}

hex_to_dec() {
  local value="${1#0x}"
  value="${value:-0}"
  printf '%d' "$((16#${value}))"
}

# ---------------------------------------------------------
# Containers
# ---------------------------------------------------------

for ((i=1; i<=VALIDATOR_COUNT; i++)); do
  container="traceforge-validator${i}"

  if ! docker inspect "${container}" >/dev/null 2>&1; then
    fail "${container} does not exist"
  fi

  state="$(
    docker inspect \
      --format '{{.State.Status}}' \
      "${container}"
  )"

  health="$(
    docker inspect \
      --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' \
      "${container}"
  )"

  if [[ "${state}" != "running" ]]; then
    fail "${container} is not running"
  fi

  if [[ "${health}" != "healthy" && "${health}" != "none" ]]; then
    fail "${container} health=${health}"
  fi

  ok "${container}: running (${health})"
done

# ---------------------------------------------------------
# RPC
# ---------------------------------------------------------

client_response="$(rpc "web3_clientVersion" "[]")" \
  || fail "RPC is not reachable at ${RPC_URL}"

ok "RPC reachable: ${RPC_URL}"

# ---------------------------------------------------------
# Chain ID
# ---------------------------------------------------------

chain_response="$(rpc "eth_chainId" "[]")" \
  || fail "Unable to query chain ID"

chain_hex="$(
  printf '%s' "${chain_response}" |
    extract_string_result
)"

expected_chain_hex="$(
  printf '0x%x' "${CHAIN_ID}"
)"

if [[ "${chain_hex}" != "${expected_chain_hex}" ]]; then
  fail "Chain ID mismatch: expected ${expected_chain_hex}, got ${chain_hex}"
fi

ok "Chain ID: ${CHAIN_ID} (${chain_hex})"

# ---------------------------------------------------------
# QBFT validator set
# ---------------------------------------------------------

validator_response="$(
  rpc \
    "qbft_getValidatorsByBlockNumber" \
    '["latest"]'
)" || fail "Unable to query QBFT validator set"

validator_addresses="$(
  printf '%s' "${validator_response}" |
    grep -oE '0x[0-9a-fA-F]{40}' || true
)"

validator_count="$(
  printf '%s\n' "${validator_addresses}" |
    sed '/^$/d' |
    wc -l |
    tr -d ' '
)"

if [[ "${validator_count}" -ne "${VALIDATOR_COUNT}" ]]; then
  fail "Expected ${VALIDATOR_COUNT} validators, found ${validator_count}"
fi

ok "QBFT validators: ${validator_count}"

# ---------------------------------------------------------
# P2P peers
# ---------------------------------------------------------

peer_response="$(rpc "net_peerCount" "[]")" \
  || fail "Unable to query peer count"

peer_hex="$(
  printf '%s' "${peer_response}" |
    extract_string_result
)"

peer_count="$(hex_to_dec "${peer_hex}")"
expected_peers=$((VALIDATOR_COUNT - 1))

if (( peer_count < expected_peers )); then
  fail "Peer count ${peer_count}; expected at least ${expected_peers}"
fi

ok "P2P peers: ${peer_count}"

# ---------------------------------------------------------
# Block production
# ---------------------------------------------------------

block1_response="$(rpc "eth_blockNumber" "[]")" \
  || fail "Unable to query block number"

block1_hex="$(
  printf '%s' "${block1_response}" |
    extract_string_result
)"

block1="$(hex_to_dec "${block1_hex}")"

wait_seconds=$((BLOCK_PERIOD_SECONDS * 2 + 1))

sleep "${wait_seconds}"

block2_response="$(rpc "eth_blockNumber" "[]")" \
  || fail "Unable to query block number"

block2_hex="$(
  printf '%s' "${block2_response}" |
    extract_string_result
)"

block2="$(hex_to_dec "${block2_hex}")"

if (( block2 <= block1 )); then
  fail "Block production stalled at block ${block1}"
fi

ok "Blocks advancing: ${block1} -> ${block2}"

if [[ "${QUIET}" == false ]]; then
  echo
  echo "TraceForge Chain is healthy."
fi
