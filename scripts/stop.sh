#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

docker compose \
  --env-file "${ROOT_DIR}/config/network.env" \
  -f "${ROOT_DIR}/docker/compose.yml" \
  down
