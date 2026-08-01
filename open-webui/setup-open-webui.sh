#!/usr/bin/env bash
# Install/start Open WebUI in Docker, wired to a local Ollama instance, and verify it comes up healthy.
set -euo pipefail

CONTAINER_NAME="${OPEN_WEBUI_CONTAINER:-open-webui}"
IMAGE="${OPEN_WEBUI_IMAGE:-ghcr.io/open-webui/open-webui:main}"
HOST_PORT="${OPEN_WEBUI_PORT:-3000}"
VOLUME_NAME="${OPEN_WEBUI_VOLUME:-open-webui}"
OLLAMA_URL="${OLLAMA_BASE_URL:-http://host.docker.internal:11434}"
OLLAMA_HOST_CHECK_URL="${OLLAMA_HOST_CHECK_URL:-http://localhost:11434}"

log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }
err() { printf '[%s] ERROR: %s\n' "$(date '+%H:%M:%S')" "$*" >&2; }

require_docker() {
  if ! command -v docker &>/dev/null; then
    err "Docker not found. Install Docker Desktop: https://www.docker.com/products/docker-desktop"
    exit 1
  fi
  if ! docker info &>/dev/null; then
    err "Docker daemon not running. Start Docker Desktop and retry."
    exit 1
  fi
}

check_ollama() {
  # This check runs on the host, so it uses the host-reachable URL, not the
  # host.docker.internal address the container will use.
  log "Checking Ollama at ${OLLAMA_HOST_CHECK_URL} ..."
  if curl -fsS --max-time 5 "${OLLAMA_HOST_CHECK_URL}/api/tags" >/dev/null 2>&1; then
    log "Ollama is reachable."
  else
    err "Cannot reach Ollama at ${OLLAMA_HOST_CHECK_URL}. Make sure 'ollama serve' is running."
    exit 1
  fi
}

find_free_port() {
  local port="${HOST_PORT}"
  while lsof -nP -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1; do
    log "Port ${port} is already in use, trying $((port + 1))..."
    port=$((port + 1))
  done
  HOST_PORT="${port}"
}

run_container() {
  if docker ps -a --format '{{.Names}}' | grep -qx "${CONTAINER_NAME}"; then
    log "Removing existing container '${CONTAINER_NAME}'..."
    docker rm -f "${CONTAINER_NAME}" >/dev/null
  fi

  find_free_port

  log "Pulling image ${IMAGE}..."
  docker pull "${IMAGE}"

  log "Starting container '${CONTAINER_NAME}' on port ${HOST_PORT}..."
  docker run -d \
    --name "${CONTAINER_NAME}" \
    -p "${HOST_PORT}:8080" \
    -e "OLLAMA_BASE_URL=${OLLAMA_URL}" \
    -v "${VOLUME_NAME}:/app/backend/data" \
    --restart unless-stopped \
    --add-host=host.docker.internal:host-gateway \
    "${IMAGE}" >/dev/null
}

wait_for_ready() {
  local url="http://localhost:${HOST_PORT}/health"
  local tries=30
  log "Waiting for Open WebUI to become healthy..."
  for ((i = 1; i <= tries; i++)); do
    if curl -fsS --max-time 3 "${url}" >/dev/null 2>&1; then
      log "Open WebUI is up: http://localhost:${HOST_PORT}"
      return 0
    fi
    sleep 2
  done
  err "Open WebUI did not become healthy within $((tries * 2))s."
  docker logs --tail 50 "${CONTAINER_NAME}" || true
  return 1
}

main() {
  require_docker
  check_ollama
  run_container
  wait_for_ready
}

main "$@"
