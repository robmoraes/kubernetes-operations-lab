#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly TIMEOUT_SECONDS=${1:-1800}
readonly STARTED_AT=$(date +%s)

command -v terraform >/dev/null || { printf '%s\n' 'terraform não encontrado.' >&2; exit 1; }
command -v aws >/dev/null || { printf '%s\n' 'aws CLI não encontrado.' >&2; exit 1; }

if [[ "$(terraform -chdir="$SCRIPT_DIR" output -raw bootstrap_control_plane)" != "true" ]]; then
  printf '%s\n' 'O laboratório está em modo manual; não existe bootstrap do CP a aguardar.' >&2
  exit 1
fi

readonly INSTANCE_ID=$(terraform -chdir="$SCRIPT_DIR" output -raw cp1_instance_id)
readonly REGION=$(terraform -chdir="$SCRIPT_DIR" output -raw region)

printf 'Aguardando bootstrap de cp1 (%s) em %s...\n' "$INSTANCE_ID" "$REGION"

while true; do
  console_output=$(aws ec2 get-console-output \
    --region "$REGION" \
    --instance-id "$INSTANCE_ID" \
    --latest \
    --query Output \
    --output text 2>/dev/null || true)

  if [[ "$console_output" == *CURSO_CONTROL_PLANE_READY* ]]; then
    printf '%s\n' 'Control plane preparado. O ingresso dos workers permanece manual.'
    exit 0
  fi

  if [[ "$console_output" == *CURSO_BOOTSTRAP_FAILED* ]]; then
    printf '%s\n' 'O bootstrap informou falha. Entre em cp1 e leia /var/log/curso-bootstrap.log.' >&2
    exit 1
  fi

  now=$(date +%s)
  if (( now - STARTED_AT >= TIMEOUT_SECONDS )); then
    printf 'Timeout após %s segundos. Consulte cloud-init e o log do bootstrap em cp1.\n' "$TIMEOUT_SECONDS" >&2
    exit 1
  fi

  sleep 15
done
