#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ENV_FILE="${ROOT_DIR}/config/network.env"
CONFIG_FILE="${ROOT_DIR}/generated/qbftConfigFile.json"
OUTPUT_DIR="${ROOT_DIR}/generated/network"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Error: ${ENV_FILE} not found."
  echo
  echo "Create it with:"
  echo "  cp config/network.env.example config/network.env"
  exit 1
fi

# shellcheck disable=SC1090
source "${ENV_FILE}"

required_variables=(
  BESU_IMAGE
  CHAIN_ID
  VALIDATOR_COUNT
  BLOCK_PERIOD_SECONDS
  REQUEST_TIMEOUT_SECONDS
  EPOCH_LENGTH
  BLOCK_REWARD
  BLOCK_GAS_LIMIT
  ZERO_BASE_FEE
)

for variable in "${required_variables[@]}"; do
  if [[ -z "${!variable:-}" ]]; then
    echo "Error: ${variable} is not configured in ${ENV_FILE}"
    exit 1
  fi
done

case "${ZERO_BASE_FEE}" in
  true|false)
    ;;
  *)
    echo "Error: ZERO_BASE_FEE must be true or false."
    exit 1
    ;;
esac

if [[ -e "${OUTPUT_DIR}/genesis.json" || -d "${OUTPUT_DIR}/keys" ]]; then
  echo "Error: A generated network already exists:"
  echo "  ${OUTPUT_DIR}"
  echo
  echo "Refusing to overwrite validator keys."
  echo "Reset the generated network explicitly before generating a new one."
  exit 1
fi

mkdir -p "${ROOT_DIR}/generated"

cat > "${CONFIG_FILE}" <<JSON
{
  "genesis": {
    "config": {
      "chainId": ${CHAIN_ID},
      "berlinBlock": 0,
      "londonBlock": 0,
      "zeroBaseFee": ${ZERO_BASE_FEE},
      "qbft": {
        "blockperiodseconds": ${BLOCK_PERIOD_SECONDS},
        "epochlength": ${EPOCH_LENGTH},
        "requesttimeoutseconds": ${REQUEST_TIMEOUT_SECONDS},
        "blockreward": "${BLOCK_REWARD}"
      }
    },
    "nonce": "0x0",
    "timestamp": "0x58ee40ba",
    "gasLimit": "${BLOCK_GAS_LIMIT}",
    "difficulty": "0x1",
    "mixHash": "0x63746963616c2062797a616e74696e65206661756c7420746f6c6572616e6365",
    "coinbase": "0x0000000000000000000000000000000000000000",
    "alloc": {}
  },
  "blockchain": {
    "nodes": {
      "generate": true,
      "count": ${VALIDATOR_COUNT}
    }
  }
}
JSON

echo "TraceForge Chain"
echo "================"
echo
echo "Besu image:       ${BESU_IMAGE}"
echo "Chain ID:         ${CHAIN_ID}"
echo "Validators:       ${VALIDATOR_COUNT}"
echo "Block period:     ${BLOCK_PERIOD_SECONDS}s"
echo "Block reward:     ${BLOCK_REWARD}"
echo "Zero base fee:    ${ZERO_BASE_FEE}"
echo

docker run --rm \
  --user "$(id -u):$(id -g)" \
  -v "${ROOT_DIR}:/network" \
  "${BESU_IMAGE}" \
  operator generate-blockchain-config \
  --config-file=/network/generated/qbftConfigFile.json \
  --to=/network/generated/network \
  --private-key-file-name=key

echo
echo "Network generated successfully."
echo
echo "Genesis:"
echo "  ${OUTPUT_DIR}/genesis.json"
echo
echo "Validator addresses:"

for validator_dir in "${OUTPUT_DIR}"/keys/*; do
  [[ -d "${validator_dir}" ]] || continue
  echo "  - $(basename "${validator_dir}")"
done
