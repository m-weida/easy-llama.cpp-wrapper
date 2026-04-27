#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
LLAMA_SERVER_CMD="${LLAMA_SERVER_CMD:-llama-server}"
NGL_DEFAULT="${NGL_DEFAULT:-99}"

if [[ -n "${HF_HUB_CACHE:-}" ]]; then
  HF_CACHE_ROOT="$HF_HUB_CACHE"
elif [[ -n "${HF_HOME:-}" ]]; then
  HF_CACHE_ROOT="$HF_HOME/hub"
else
  HF_CACHE_ROOT="$HOME/.cache/huggingface/hub"
fi

declare -a MODELS=()

print_help() {
  cat <<EOF
Usage:
  $SCRIPT_NAME list
  $SCRIPT_NAME start <index|query|/path/to/model.gguf> [llama-server args...]
  $SCRIPT_NAME hf <repo-id> [llama-server args...]
  $SCRIPT_NAME help

Commands:
  list    List downloaded GGUF models from Hugging Face cache.
  start   Start llama-server with a local GGUF model and -ngl $NGL_DEFAULT.
  hf      Start llama-server directly from a Hugging Face repo via -hf.
  help    Show this help.

Examples:
  $SCRIPT_NAME list
  $SCRIPT_NAME start 1
  $SCRIPT_NAME start gemma-4-E4B-it-Q4_K_M
  $SCRIPT_NAME start ~/models/mistral.gguf --port 8080
  $SCRIPT_NAME hf ggml-org/gemma-4-e4b-it-GGUF --port 8080

Config (optional env vars):
  LLAMA_SERVER_CMD  Command to run llama server (default: llama-server)
  NGL_DEFAULT       Default value for -ngl (default: 99)
  HF_HUB_CACHE      Hugging Face hub cache directory
  HF_HOME           Hugging Face home directory (uses \$HF_HOME/hub)
EOF
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: required command not found: $1" >&2
    exit 1
  fi
}

model_repo_from_path() {
  local model_path="$1"
  local rel owner repo

  rel="${model_path#*models--}"
  rel="${rel%%/snapshots/*}"

  if [[ "$rel" == "$model_path" || -z "$rel" ]]; then
    echo "unknown/unknown"
    return
  fi

  owner="${rel%%--*}"
  repo="${rel#*--}"
  echo "$owner/$repo"
}

collect_models() {
  MODELS=()

  if [[ ! -d "$HF_CACHE_ROOT" ]]; then
    return
  fi

  while IFS= read -r path; do
    if [[ "$(basename "$path")" == mmproj-* ]]; then
      continue
    fi
    MODELS+=("$path")
  done < <(find "$HF_CACHE_ROOT" \( -type f -o -type l \) \( -name '*.gguf' -o -name '*.GGUF' \) 2>/dev/null | sort)
}

print_model_line() {
  local idx="$1"
  local model_path="$2"
  local repo file

  repo="$(model_repo_from_path "$model_path")"
  file="$(basename "$model_path")"

  printf "%3s | %s | %s\n" "$idx" "$repo" "$file"
  printf "      %s\n" "$model_path"
}

cmd_list() {
  collect_models

  if [[ ${#MODELS[@]} -eq 0 ]]; then
    cat <<EOF
No GGUF files found in Hugging Face cache:
  $HF_CACHE_ROOT

Tip: run llama-server with -hf once, then list again.
EOF
    return 0
  fi

  echo "Found ${#MODELS[@]} GGUF file(s) in $HF_CACHE_ROOT"
  echo

  local i idx
  for i in "${!MODELS[@]}"; do
    idx=$((i + 1))
    print_model_line "$idx" "${MODELS[$i]}"
  done
}

resolve_model() {
  local input="$1"

  if [[ "$input" == *.gguf || "$input" == *.GGUF ]]; then
    local expanded_input
    expanded_input="${input/#\~/$HOME}"
    if [[ -f "$expanded_input" ]]; then
      printf "%s\n" "$expanded_input"
      return 0
    fi
  fi

  collect_models
  if [[ ${#MODELS[@]} -eq 0 ]]; then
    echo "Error: no cached GGUF models found in $HF_CACHE_ROOT" >&2
    return 1
  fi

  if [[ "$input" =~ ^[0-9]+$ ]]; then
    local idx=$((input - 1))
    if (( idx < 0 || idx >= ${#MODELS[@]} )); then
      echo "Error: model index out of range: $input" >&2
      return 1
    fi
    printf "%s\n" "${MODELS[$idx]}"
    return 0
  fi

  local lowered_input
  lowered_input="$(printf "%s" "$input" | tr '[:upper:]' '[:lower:]')"

  local -a matches=()
  local i path repo file lowered_candidate
  for i in "${!MODELS[@]}"; do
    path="${MODELS[$i]}"
    repo="$(model_repo_from_path "$path")"
    file="$(basename "$path")"
    lowered_candidate="$(printf "%s %s %s" "$path" "$repo" "$file" | tr '[:upper:]' '[:lower:]')"
    if [[ "$lowered_candidate" == *"$lowered_input"* ]]; then
      matches+=("$i")
    fi
  done

  if [[ ${#matches[@]} -eq 0 ]]; then
    echo "Error: no model matched query: $input" >&2
    return 1
  fi

  if [[ ${#matches[@]} -gt 1 ]]; then
    echo "Error: query matched multiple models. Please use an index or a more specific query:" >&2
    local midx shown
    for midx in "${matches[@]}"; do
      shown=$((midx + 1))
      print_model_line "$shown" "${MODELS[$midx]}" >&2
    done
    return 1
  fi

  printf "%s\n" "${MODELS[${matches[0]}]}"
}

cmd_start() {
  if [[ $# -lt 1 ]]; then
    echo "Error: start requires <index|query|path>" >&2
    print_help
    exit 1
  fi

  require_command "$LLAMA_SERVER_CMD"

  local model_ref="$1"
  shift

  local model_path
  model_path="$(resolve_model "$model_ref")"

  echo "Using model: $model_path"
  echo "Running: $LLAMA_SERVER_CMD -m \"$model_path\" -ngl $NGL_DEFAULT $*"

  "$LLAMA_SERVER_CMD" -m "$model_path" -ngl "$NGL_DEFAULT" "$@"
}

cmd_hf() {
  if [[ $# -lt 1 ]]; then
    echo "Error: hf requires <repo-id>" >&2
    print_help
    exit 1
  fi

  require_command "$LLAMA_SERVER_CMD"

  local repo_id="$1"
  shift

  echo "Running: $LLAMA_SERVER_CMD -hf \"$repo_id\" -ngl $NGL_DEFAULT $*"
  "$LLAMA_SERVER_CMD" -hf "$repo_id" -ngl "$NGL_DEFAULT" "$@"
}

main() {
  local cmd="${1:-help}"

  case "$cmd" in
    list)
      shift
      cmd_list "$@"
      ;;
    start)
      shift
      cmd_start "$@"
      ;;
    hf)
      shift
      cmd_hf "$@"
      ;;
    help|-h|--help)
      print_help
      ;;
    *)
      echo "Error: unknown command: $cmd" >&2
      print_help
      exit 1
      ;;
  esac
}

main "$@"
