#!/usr/bin/env bash
set -Eeuo pipefail

cd /app
export PYTHONPATH="/app/src${PYTHONPATH:+:$PYTHONPATH}"
export STORAGE_BACKEND="${STORAGE_BACKEND:-sqlite}"
export DATABASE_PATH="${DATABASE_PATH:-/app/data/yt-dlp-host.sqlite3}"
export JSON_STATE_FILE="${JSON_STATE_FILE:-/app/jsons/.yt-dlp-host-state.json}"
export DOWNLOAD_DIR="${DOWNLOAD_DIR:-/app/downloads}"
export LEGACY_KEYS_FILE="${LEGACY_KEYS_FILE:-/app/jsons/api_keys.json}"
export LEGACY_TASKS_FILE="${LEGACY_TASKS_FILE:-/app/jsons/tasks.json}"

mkdir -p "$(dirname "$DATABASE_PATH")" "$(dirname "$JSON_STATE_FILE")" "$DOWNLOAD_DIR" "$(dirname "$LEGACY_KEYS_FILE")"
python -c 'import yt_dlp_host.worker; import gunicorn' || { echo 'Required modules unavailable' >&2; exit 1; }

worker_pid=''
api_pid=''
cleanup() {
  trap - TERM INT EXIT
  if [[ -n "$worker_pid" ]]; then kill -TERM "$worker_pid" 2>/dev/null || true; fi
  if [[ -n "$api_pid" ]]; then kill -TERM "$api_pid" 2>/dev/null || true; fi
  if [[ -n "$worker_pid" ]]; then wait "$worker_pid" 2>/dev/null || true; fi
  if [[ -n "$api_pid" ]]; then wait "$api_pid" 2>/dev/null || true; fi
}
trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

python -m yt_dlp_host.worker &
worker_pid=$!
echo "RAILWAY_YTDLP_WORKER_STARTED pid=$worker_pid"
gunicorn -c gunicorn.conf.py src.server:app &
api_pid=$!
echo "RAILWAY_YTDLP_API_STARTED pid=$api_pid port=${PORT:-5000}"

# If either process exits, stop the other and trigger a Railway restart.
set +e
wait -n "$worker_pid" "$api_pid"
exit_code=$?
set -e
echo "RAILWAY_YTDLP_PROCESS_EXIT code=$exit_code; stopping sibling" >&2
# Do not appear healthy if one process unexpectedly exited with status 0.
if [[ "$exit_code" -eq 0 ]]; then exit 1; fi
exit "$exit_code"
