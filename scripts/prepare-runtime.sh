#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ENV_FILE="${ROOT_DIR}/config/network.env"
GENERATED_DIR="${ROOT_DIR}/generated/network"
KEYS_DIR="${GENERATED_DIR}/keys"
GENESIS_FILE="${GENERATED_DIR}/genesis.json"
RUNTIME_DIR="${ROOT_DIR}/runtime"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Error: ${ENV_FILE} not found."
  exit 1
fi

# shellcheck disable=SC1090
source "${ENV_FILE}"

if [[ ! -f "${GENESIS_FILE}" ]]; then
  echo "Error: Generated genesis not found."
  echo
  echo "Run:"
  echo "  ./scripts/generate-network.sh"
  exit 1
fi

if [[ ! -d "${KEYS_DIR}" ]]; then
  echo "Error: Generated validator keys not found."
  exit 1
fi

validator_dirs=()

while IFS= read -r validator_dir; do
  validator_dirs+=("${validator_dir}")
done < <(
  find "${KEYS_DIR}" \
    -mindepth 1 \
    -maxdepth 1 \
    -type d \
    | sort
)

actual_count="${#validator_dirs[@]}"

if [[ "${actual_count}" -ne "${VALIDATOR_COUNT}" ]]; then
  echo "Error: Validator count mismatch."
  echo
  echo "Configured: ${VALIDATOR_COUNT}"
  echo "Generated:  ${actual_count}"
  exit 1
fi

if [[ -d "${RUNTIME_DIR}" ]] &&
   [[ -n "$(find "${RUNTIME_DIR}" -mindepth 1 -print -quit 2>/dev/null)" ]]; then

  echo "Error: Runtime directory already contains data:"
  echo "  ${RUNTIME_DIR}"
  echo
  echo "Refusing to overwrite an existing blockchain runtime."
  exit 1
fi

mkdir -p "${RUNTIME_DIR}/shared"

cp "${GENESIS_FILE}" \
   "${RUNTIME_DIR}/shared/genesis.json"

VALIDATOR_MAP="${RUNTIME_DIR}/shared/validators.txt"

: > "${VALIDATOR_MAP}"

index=1

for source_dir in "${validator_dirs[@]}"; do

  validator_name="validator${index}"
  validator_address="$(basename "${source_dir}")"

  target_dir="${RUNTIME_DIR}/${validator_name}/data"

  mkdir -p "${target_dir}"

  cp "${source_dir}/key" \
     "${target_dir}/key"

  cp "${source_dir}/key.pub" \
     "${target_dir}/key.pub"

  chmod 700 "${RUNTIME_DIR}/${validator_name}"
  chmod 700 "${target_dir}"
  chmod 600 "${target_dir}/key"
  chmod 644 "${target_dir}/key.pub"

  printf "%s=%s\n" \
    "${validator_name}" \
    "${validator_address}" \
    >> "${VALIDATOR_MAP}"

  index=$((index + 1))
done

echo
echo "TraceForge runtime prepared successfully."
echo
echo "Genesis:"
echo "  runtime/shared/genesis.json"
echo
echo "Validators:"
cat "${VALIDATOR_MAP}"
echo
echo "Runtime directory:"
echo "  ${RUNTIME_DIR}"
