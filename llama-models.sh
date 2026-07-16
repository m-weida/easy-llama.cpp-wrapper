#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${BASH_VERSION:-}" ]]; then
  echo "Error: $0 must be run with Bash, not zsh or sh." >&2
  exit 1
fi

if (( BASH_VERSINFO[0] < 3 || (BASH_VERSINFO[0] == 3 && BASH_VERSINFO[1] < 2) )); then
  echo "Error: $0 requires Bash 3.2 or newer (found $BASH_VERSION)." >&2
  exit 1
fi

SCRIPT_NAME="$(basename "$0")"

normalize_platform_path() {
  local path="$1"

  # Git Bash accepts both /c/... and C:/... paths, but its Unix tools are
  # more reliable with the former. Normalize native Windows paths at the
  # shell boundary while leaving POSIX paths unchanged elsewhere.
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
      if [[ "$path" =~ ^[A-Za-z]:[\\/].* ]] && command -v cygpath >/dev/null 2>&1; then
        cygpath -u "$path"
        return
      fi
      ;;
  esac

  printf "%s\n" "$path"
}

resolve_physical_path() {
  local path="$1"
  local link_target dir

  path="${path/#\~/$HOME}"
  path="$(normalize_platform_path "$path")"

  if [[ "$path" != /* ]]; then
    path="$PWD/$path"
  fi

  while [[ -L "$path" ]]; do
    link_target="$(readlink "$path")"
    if [[ "$link_target" == /* ]]; then
      path="$link_target"
    else
      dir="$(cd -- "$(dirname -- "$path")" && pwd -P)"
      path="$dir/$link_target"
    fi
  done

  dir="$(cd -- "$(dirname -- "$path")" && pwd -P)"
  printf "%s/%s\n" "$dir" "$(basename -- "$path")"
}

SCRIPT_PATH="$(resolve_physical_path "${BASH_SOURCE[0]}")"
LLAMA_SERVER_CMD="${LLAMA_SERVER_CMD:-llama-server}"
LLAMA_SERVER_CMD="$(normalize_platform_path "$LLAMA_SERVER_CMD")"
LLAMA_FIT_PARAMS_CMD="${LLAMA_FIT_PARAMS_CMD:-llama-fit-params}"
LLAMA_FIT_PARAMS_CMD="$(normalize_platform_path "$LLAMA_FIT_PARAMS_CMD")"
LLAMA_AUTO_MMPROJ="${LLAMA_AUTO_MMPROJ:-1}"
LLAMA_ENABLE_TOOLS="${LLAMA_ENABLE_TOOLS:-1}"
LLAMA_DEFAULT_TOOLS="${LLAMA_DEFAULT_TOOLS:-read_file,file_glob_search,grep_search,get_datetime}"
LLAMA_DEFAULT_CTK="${LLAMA_DEFAULT_CTK:-q8_0}"
LLAMA_DEFAULT_CTV="${LLAMA_DEFAULT_CTV:-q8_0}"
LLAMA_DEFAULT_NP="${LLAMA_DEFAULT_NP:-1}"
LLAMA_DEFAULT_FA="${LLAMA_DEFAULT_FA:-on}"
LLAMA_AUTO_MTP="${LLAMA_AUTO_MTP:-1}"
LLAMA_DEFAULT_SPEC_DRAFT_N_MAX="${LLAMA_DEFAULT_SPEC_DRAFT_N_MAX:-2}"

if [[ -n "${HF_HUB_CACHE:-}" ]]; then
  HF_CACHE_ROOT="$HF_HUB_CACHE"
elif [[ -n "${HF_HOME:-}" ]]; then
  HF_CACHE_ROOT="$HF_HOME/hub"
else
  HF_CACHE_ROOT="$HOME/.cache/huggingface/hub"
fi
HF_CACHE_ROOT="$(normalize_platform_path "$HF_CACHE_ROOT")"

declare -a MODELS=()

print_help() {
  cat <<EOF
Usage:
  $SCRIPT_NAME list [--paths, -p]
  $SCRIPT_NAME start <index|query|/path/to/model.gguf> [llama-server args...]
  $SCRIPT_NAME remove <index|query|/path/to/model.gguf>
  $SCRIPT_NAME hf <repo-id> [llama-server args...]
  $SCRIPT_NAME fit-params <index|query|/path/to/model.gguf> [llama-fit-params args...]
  $SCRIPT_NAME fit-params -hf <repo-id>[:quant] [llama-fit-params args...]
  $SCRIPT_NAME check-updates
  $SCRIPT_NAME update [--clean] <index|query|repo-id> [llama-server args...]
  $SCRIPT_NAME install [target-link-path]
  $SCRIPT_NAME uninstall [target-link-path]
  $SCRIPT_NAME help

Commands:
  list           List downloaded GGUF models from Hugging Face cache.
                 Pass --paths (or -p) to also print each model's full path.
  start          Start llama-server with a local GGUF model.
                 Auto-loads a sibling MTP draft model (mtp-*.gguf) when found,
                 using --model-draft <mtp> --spec-type draft-mtp
                 --spec-draft-n-max $LLAMA_DEFAULT_SPEC_DRAFT_N_MAX.
  remove         Preview and remove a local GGUF model plus safe associated files.
  hf             Start llama-server directly from a Hugging Face repo via -hf.
                 MTP remains opt-in because not every repo provides a compatible draft model.
  fit-params     Test whether a model fits in device memory via llama-fit-params.
                 Prints the fitted CLI arguments (-c/-ngl chosen by --fit) by
                 default; append -fitp on to print the estimated memory
                 (model/context/compute) per device instead.
                 Applies the same -ctk/-ctv/-np/-fa defaults as start/hf;
                 mmproj/MTP are not auto-loaded because llama-fit-params does
                 not accept them.
  check-updates  Check cached Hugging Face repos for newer commits on the
                 default branch and report which models have updates.
  update         Re-run llama-server -hf for a repo to fetch the latest version.
                 Pass --clean to delete the old cached files first.
  install        Create a symlink to this script after confirming the target path.
  uninstall      Remove the symlink created by install after confirming it points here.
  help           Show this help.

Default llama-server flags (added for start/hf unless overridden):
  -ctk $LLAMA_DEFAULT_CTK, -ctv $LLAMA_DEFAULT_CTV,
  -np $LLAMA_DEFAULT_NP, -fa $LLAMA_DEFAULT_FA

--jinja is enabled by default in llama-server, so the wrapper does not add it;
pass --no-jinja to opt out. -ngl is not added either; --fit (on by default)
tunes it to fit device memory, so pass -ngl explicitly to pin a value.
fit-params applies the same -ctk/-ctv/-np/-fa defaults but omits --tools,
which llama-fit-params does not support.

Examples:
  $SCRIPT_NAME list
  $SCRIPT_NAME list --paths
  $SCRIPT_NAME start 1
  $SCRIPT_NAME start gemma-4-E4B-it-Q4_K_M
  $SCRIPT_NAME start ~/models/mistral.gguf --port 8080
  LLAMA_ENABLE_TOOLS=0 $SCRIPT_NAME start 1
  LLAMA_DEFAULT_TOOLS=all $SCRIPT_NAME start 1
  $SCRIPT_NAME remove 1
  $SCRIPT_NAME hf ggml-org/gemma-4-e4b-it-GGUF --port 8080
  $SCRIPT_NAME fit-params 1
  $SCRIPT_NAME fit-params gemma-4-E4B-it-Q4_K_M
  $SCRIPT_NAME fit-params -hf unsloth/Qwen3.6-27B-MTP-GGUF:UD-Q4_K_XL
  $SCRIPT_NAME fit-params 1 -c 32768 -fit off
  $SCRIPT_NAME check-updates
  $SCRIPT_NAME update 1
  $SCRIPT_NAME update unsloth/gemma-4-12B-it-qat-GGUF
  $SCRIPT_NAME update --clean 1
  $SCRIPT_NAME install
  $SCRIPT_NAME install ~/bin/llama-models
  $SCRIPT_NAME uninstall

Config (optional env vars):
  LLAMA_SERVER_CMD  Command to run llama server (default: llama-server)
  LLAMA_FIT_PARAMS_CMD
                    Command to run llama-fit-params (default: llama-fit-params)
  LLAMA_ENABLE_TOOLS
                    Enable default tools; set to 0/false/no/off to opt out
  LLAMA_DEFAULT_TOOLS
                    Default --tools value (default: read_file,file_glob_search,
                    grep_search,get_datetime; set to all to opt in to all tools)
  LLAMA_DEFAULT_CTK Default value for -ctk (default: q8_0)
  LLAMA_DEFAULT_CTV Default value for -ctv (default: q8_0)
  LLAMA_DEFAULT_NP  Default value for -np (default: 1)
  LLAMA_DEFAULT_FA  Default value for -fa (default: on)
  LLAMA_AUTO_MTP    Auto-load MTP draft models for supported models (default: 1)
  LLAMA_DEFAULT_SPEC_DRAFT_N_MAX
                    Default value for --spec-draft-n-max (default: 2)
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

usage_error() {
  echo "Error: $1" >&2
  print_help
  exit 1
}

default_install_target() {
  printf "%s\n" "$HOME/llama-models.sh"
}

resolve_target_path() {
  local input="${1:-$(default_install_target)}"

  input="${input/#\~/$HOME}"
  input="$(normalize_platform_path "$input")"

  if [[ "$input" != /* ]]; then
    printf "%s\n" "$PWD/$input"
    return
  fi

  printf "%s\n" "$input"
}

confirm() {
  local prompt="$1"
  local response

  printf "%s [y/N] " "$prompt"
  if ! IFS= read -r response < /dev/tty; then
    printf "\nAborted.\n" >&2
    return 1
  fi

  case "$response" in
    y|Y|yes|YES)
      return 0
      ;;
    *)
      echo "Aborted." >&2
      return 1
      ;;
  esac
}

is_windows_environment() {
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

to_native_path() {
  local path="$1"

  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$path"
    return
  fi

  printf "%s\n" "$path"
}

create_symlink() {
  local source_path="$1"
  local target_path="$2"

  if is_windows_environment; then
    local source_native target_native

    source_native="$(to_native_path "$source_path")"
    target_native="$(to_native_path "$target_path")"

    if command -v powershell.exe >/dev/null 2>&1; then
      powershell.exe -NoProfile -NonInteractive -Command '& { param([string]$LinkPath, [string]$TargetPath) $ErrorActionPreference = "Stop"; New-Item -ItemType SymbolicLink -Path $LinkPath -Target $TargetPath | Out-Null }' "$target_native" "$source_native"
      return $?
    fi

    if command -v cmd.exe >/dev/null 2>&1; then
      cmd.exe //c mklink "$target_native" "$source_native" > /dev/null
      return $?
    fi

    return 1
  fi

  ln -s "$source_path" "$target_path"
}

link_points_to_source() {
  local target_path="$1"
  local source_path="$2"
  local resolved_target

  if [[ ! -L "$target_path" ]]; then
    return 1
  fi

  resolved_target="$(resolve_physical_path "$target_path")"
  [[ "$resolved_target" == "$source_path" ]]
}

normalize_for_search() {
  local text="$1"

  # Lowercase and normalize separators so token search is punctuation-insensitive.
  printf "%s" "$text" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/ /g; s/^ +//; s/ +$//; s/ +/ /g'
}

candidate_matches_query() {
  local candidate="$1"
  local query="$2"
  local normalized_candidate normalized_query token

  normalized_candidate="$(normalize_for_search "$candidate")"
  normalized_query="$(normalize_for_search "$query")"

  if [[ -z "$normalized_query" ]]; then
    return 1
  fi

  for token in $normalized_query; do
    if [[ " $normalized_candidate " != *" $token "* ]]; then
      return 1
    fi
  done

  return 0
}

candidate_token_score() {
  local candidate="$1"
  local query="$2"
  local normalized_candidate normalized_query token
  local score=0

  normalized_candidate="$(normalize_for_search "$candidate")"
  normalized_query="$(normalize_for_search "$query")"

  if [[ -z "$normalized_query" ]]; then
    printf "0\n"
    return
  fi

  for token in $normalized_query; do
    if [[ " $normalized_candidate " == *" $token "* ]]; then
      score=$((score + 1))
    fi
  done

  printf "%s\n" "$score"
}

autoload_mmproj_enabled() {
  case "$LLAMA_AUTO_MMPROJ" in
    0|false|no|off)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

autoload_mtp_enabled() {
  case "$LLAMA_AUTO_MTP" in
    0|false|no|off)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

tools_enabled() {
  case "$LLAMA_ENABLE_TOOLS" in
    0|false|no|off)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

has_mmproj_arg() {
  local arg

  for arg in "$@"; do
    case "$arg" in
      --mmproj|--mmproj=*|--mmproj-file|--mmproj-file=*)
        return 0
        ;;
    esac
  done

  return 1
}

has_tools_arg() {
  local arg

  for arg in "$@"; do
    case "$arg" in
      --tools|--tools=*)
        return 0
        ;;
    esac
  done

  return 1
}

has_ctk_arg() {
  local arg

  for arg in "$@"; do
    case "$arg" in
      -ctk|--cache-type-k|--cache-type-k=*)
        return 0
        ;;
    esac
  done

  return 1
}

has_ctv_arg() {
  local arg

  for arg in "$@"; do
    case "$arg" in
      -ctv|--cache-type-v|--cache-type-v=*)
        return 0
        ;;
    esac
  done

  return 1
}

has_np_arg() {
  local arg

  for arg in "$@"; do
    case "$arg" in
      -np|--parallel|--parallel=*)
        return 0
        ;;
    esac
  done

  return 1
}

has_fa_arg() {
  local arg

  for arg in "$@"; do
    case "$arg" in
      -fa|--flash-attn|--flash-attn=*)
        return 0
        ;;
    esac
  done

  return 1
}

has_model_draft_arg() {
  local arg

  for arg in "$@"; do
    case "$arg" in
      --model-draft|--model-draft=*)
        return 0
        ;;
    esac
  done

  return 1
}

has_spec_type_arg() {
  local arg

  for arg in "$@"; do
    case "$arg" in
      --spec-type|--spec-type=*)
        return 0
        ;;
    esac
  done

  return 1
}

has_spec_draft_n_max_arg() {
  local arg

  for arg in "$@"; do
    case "$arg" in
      --spec-draft-n-max|--spec-draft-n-max=*)
        return 0
        ;;
    esac
  done

  return 1
}

default_tools_value() {
  printf "%s\n" "$LLAMA_DEFAULT_TOOLS"
}

# Assemble default llama.cpp flags for the given mode, append the caller's
# arguments, then execute the matching binary.
#
# Modes:
#   server      llama-server: adds --tools defaults
#   fit-params  llama-fit-params: no --tools (the tool does not accept them)
#               and no mmproj/MTP auto-loading
#
# Both modes share the KV-cache and perf defaults (-ctk, -ctv, -np, -fa),
# each skipped when the caller already passes the corresponding flag. --jinja
# is not added because llama-server enables it by default (pass --no-jinja to
# opt out); -ngl is not added because --fit (on by default) tunes it.
#
# Bash 3.2 (the version shipped with macOS) has no nameref variables, so the
# base arguments are passed as a count followed by their values, then the
# user arguments.
run_llama_tool() {
  local mode="$1"
  local base_arg_count="$2"
  shift 2
  local -a args=()
  local i

  for ((i = 0; i < base_arg_count; i++)); do
    args+=("$1")
    shift
  done

  if [[ "$mode" == "server" ]]; then
    if tools_enabled && ! has_tools_arg "$@"; then
      args+=("--tools" "$(default_tools_value)")
    fi
  fi

  if ! has_ctk_arg "$@"; then
    args+=("-ctk" "$LLAMA_DEFAULT_CTK")
  fi
  if ! has_ctv_arg "$@"; then
    args+=("-ctv" "$LLAMA_DEFAULT_CTV")
  fi
  if ! has_np_arg "$@"; then
    args+=("-np" "$LLAMA_DEFAULT_NP")
  fi
  if ! has_fa_arg "$@"; then
    args+=("-fa" "$LLAMA_DEFAULT_FA")
  fi

  if [[ $# -gt 0 ]]; then
    args+=("$@")
  fi

  local cmd
  case "$mode" in
    fit-params) cmd="$LLAMA_FIT_PARAMS_CMD" ;;
    *)          cmd="$LLAMA_SERVER_CMD" ;;
  esac

  echo "Running: $cmd ${args[*]}"
  "$cmd" "${args[@]}"
}

fetch_latest_sha() {
  local repo_id="$1"
  local api_url="https://huggingface.co/api/models/$repo_id"
  local response

  response="$(curl -s --max-time 30 "$api_url" 2>/dev/null)"
  if [[ -z "$response" ]]; then
    return 1
  fi

  if command -v jq >/dev/null 2>&1; then
    printf "%s" "$response" | jq -r '.sha // empty'
    return
  fi

  # Fallback: extract the top-level sha from a flat JSON object.
  printf "%s" "$response" | sed -n 's/^[[:space:]]*{[^{}]*"sha"[[:space:]]*:[[:space:]]*"\([^"]*\)"[^{}]*}.*/\1/p'
}

find_mmproj_for_model() {
  local model_path="$1"
  local model_dir candidate candidate_path
  local -a candidates=()
  local -a scores=()
  local i best_score=0 best_idx=-1 best_tied=0 score
  local model_text

  model_dir="$(dirname "$model_path")"
  model_text="$(basename "$model_path")"

  while IFS= read -r candidate; do
    candidate_path="$candidate"
    candidates+=("$candidate_path")
    scores+=("$(candidate_token_score "$(basename "$candidate_path")" "$model_text")")
  done < <(
    # match any file containing 'mmproj' (e.g. 'mmproj-...', 'name.mmproj-...', etc.)
    find "$model_dir" -maxdepth 1 \( -type f -o -type l \) -iname '*mmproj*' 2>/dev/null | sort
  )

  if [[ ${#candidates[@]} -eq 0 ]]; then
    return 1
  fi

  if [[ ${#candidates[@]} -eq 1 ]]; then
    echo "Info: auto-selected mmproj: ${candidates[0]}" >&2
    printf "%s\n" "${candidates[0]}"
    return 0
  fi

  for i in "${!candidates[@]}"; do
    score="${scores[$i]}"
    if (( score > best_score )); then
      best_score=$score
      best_idx=$i
      best_tied=0
    elif (( score > 0 && score == best_score )); then
      best_tied=1
    fi
  done

  if (( best_score > 0 && best_tied == 0 && best_idx >= 0 )); then
    echo "Info: auto-selected mmproj: ${candidates[$best_idx]}" >&2
    printf "%s\n" "${candidates[$best_idx]}"
    return 0
  fi

  echo "Warning: found multiple mmproj candidates next to model, but could not choose one unambiguously." >&2
  for candidate in "${candidates[@]}"; do
    echo "  $candidate" >&2
  done
  return 1
}

mmproj_is_shared() {
  local mmproj_path="$1"
  local model_path="$2"
  local model_dir sibling_path sibling_mmproj_path
  local resolved_mmproj resolved_sibling_mmproj

  model_dir="$(dirname "$model_path")"
  resolved_mmproj="$(resolve_physical_path "$mmproj_path")"

  while IFS= read -r sibling_path; do
    if [[ "$sibling_path" == "$model_path" ]]; then
      continue
    fi

    if ! sibling_mmproj_path="$(find_mmproj_for_model "$sibling_path" 2>/dev/null)"; then
      continue
    fi

    resolved_sibling_mmproj="$(resolve_physical_path "$sibling_mmproj_path")"
    if [[ "$resolved_sibling_mmproj" == "$resolved_mmproj" ]]; then
      return 0
    fi
  done < <(
    find "$model_dir" -maxdepth 1 \( -type f -o -type l \) \
      \( -name '*.gguf' -o -name '*.GGUF' \) \
      ! -iname '*mmproj*' 2>/dev/null | sort
  )

  return 1
}

find_mtp_for_model() {
  local model_path="$1"
  local model_dir candidate candidate_path
  local -a candidates=()
  local -a scores=()
  local i best_score=0 best_idx=-1 best_tied=0 score
  local model_text

  model_dir="$(dirname "$model_path")"
  model_text="$(basename "$model_path")"

  while IFS= read -r candidate; do
    candidate_path="$candidate"
    candidates+=("$candidate_path")
    scores+=("$(candidate_token_score "$(basename "$candidate_path")" "$model_text")")
  done < <(
    find "$model_dir" -maxdepth 1 \( -type f -o -type l \) -iname 'mtp-*.gguf' 2>/dev/null | sort
  )

  if [[ ${#candidates[@]} -eq 0 ]]; then
    return 1
  fi

  if [[ ${#candidates[@]} -eq 1 ]]; then
    echo "Info: auto-selected MTP draft model: ${candidates[0]}" >&2
    printf "%s\n" "${candidates[0]}"
    return 0
  fi

  for i in "${!candidates[@]}"; do
    score="${scores[$i]}"
    if (( score > best_score )); then
      best_score=$score
      best_idx=$i
      best_tied=0
    elif (( score > 0 && score == best_score )); then
      best_tied=1
    fi
  done

  if (( best_score > 0 && best_tied == 0 && best_idx >= 0 )); then
    echo "Info: auto-selected MTP draft model: ${candidates[$best_idx]}" >&2
    printf "%s\n" "${candidates[$best_idx]}"
    return 0
  fi

  echo "Warning: found multiple MTP candidates next to model, but could not choose one unambiguously." >&2
  for candidate in "${candidates[@]}"; do
    echo "  $candidate" >&2
  done
  return 1
}

mtp_is_shared() {
  local mtp_path="$1"
  local model_path="$2"
  local model_dir sibling_path sibling_mtp_path
  local resolved_mtp resolved_sibling_mtp

  model_dir="$(dirname "$model_path")"
  resolved_mtp="$(resolve_physical_path "$mtp_path")"

  while IFS= read -r sibling_path; do
    if [[ "$sibling_path" == "$model_path" ]]; then
      continue
    fi

    if ! sibling_mtp_path="$(find_mtp_for_model "$sibling_path" 2>/dev/null)"; then
      continue
    fi

    resolved_sibling_mtp="$(resolve_physical_path "$sibling_mtp_path")"
    if [[ "$resolved_sibling_mtp" == "$resolved_mtp" ]]; then
      return 0
    fi
  done < <(
    find "$model_dir" -maxdepth 1 \( -type f -o -type l \) \
      \( -name '*.gguf' -o -name '*.GGUF' \) \
      ! -iname '*mmproj*' \
      ! -iname 'mtp-*.gguf' 2>/dev/null | sort
  )

  return 1
}

collect_removal_targets() {
  local model_path="$1"
  local -a targets=("$model_path")
  local mmproj_path mtp_path

  if mmproj_path="$(find_mmproj_for_model "$model_path")"; then
    if mmproj_is_shared "$mmproj_path" "$model_path"; then
      echo "Info: mmproj is shared with other model(s), keeping: $mmproj_path" >&2
    else
      targets+=("$mmproj_path")
    fi
  fi

  if mtp_path="$(find_mtp_for_model "$model_path")"; then
    if mtp_is_shared "$mtp_path" "$model_path"; then
      echo "Info: MTP draft model is shared with other model(s), keeping: $mtp_path" >&2
    else
      targets+=("$mtp_path")
    fi
  fi

  printf "%s\n" "${targets[@]}"
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
    local base base_lower
    base="$(basename "$path")"
    base_lower="$(printf "%s" "$base" | tr '[:upper:]' '[:lower:]')"
    # skip GGUF files that were generated from .mmproj exports
    # (they often include the substring 'mmproj' in the filename)
    if [[ "$base" == *mmproj* ]]; then
      continue
    fi
    # skip standalone MTP draft models; they are loaded alongside the main model
    if [[ "$base_lower" == mtp-*.gguf ]]; then
      continue
    fi
    MODELS+=("$path")
  done < <(find "$HF_CACHE_ROOT" \( -type f -o -type l \) \( -name '*.gguf' -o -name '*.GGUF' \) 2>/dev/null | sort)
}

print_model_line() {
  local idx="$1"
  local model_path="$2"
  local show_path="${3:-0}"
  local repo file

  repo="$(model_repo_from_path "$model_path")"
  file="$(basename "$model_path")"

  printf "%3s | %s | %s\n" "$idx" "$repo" "$file"
  if [[ "$show_path" == "1" ]]; then
    printf "      %s\n" "$model_path"
  fi
}

cmd_list() {
  local show_paths=0
  local arg

  while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
      --paths|-p)
        show_paths=1
        shift
        ;;
      --)
        shift
        break
        ;;
      *)
        echo "Error: list does not accept argument: $arg" >&2
        echo "Usage: $SCRIPT_NAME list [--paths]" >&2
        return 1
        ;;
    esac
  done

  if [[ $# -gt 0 ]]; then
    echo "Error: list does not accept positional arguments: $*" >&2
    echo "Usage: $SCRIPT_NAME list [--paths]" >&2
    return 1
  fi
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
    print_model_line "$idx" "${MODELS[$i]}" "$show_paths"
  done
}

resolve_model() {
  local input="$1"

  if [[ "$input" == *.gguf || "$input" == *.GGUF ]]; then
    local expanded_input
    expanded_input="${input/#\~/$HOME}"
    expanded_input="$(normalize_platform_path "$expanded_input")"
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

  local -a matches=()
  local i path repo file candidate_text
  for i in "${!MODELS[@]}"; do
    path="${MODELS[$i]}"
    repo="$(model_repo_from_path "$path")"
    file="$(basename "$path")"
    candidate_text="$(printf "%s %s %s" "$path" "$repo" "$file")"
    if candidate_matches_query "$candidate_text" "$input"; then
      matches+=("$i")
    fi
  done

  if [[ ${#matches[@]} -eq 0 ]]; then
    # Fallback: choose the unique best partial token match.
    local best_score=0
    local best_idx=-1
    local best_tied=0
    local score

    for i in "${!MODELS[@]}"; do
      path="${MODELS[$i]}"
      repo="$(model_repo_from_path "$path")"
      file="$(basename "$path")"
      candidate_text="$(printf "%s %s %s" "$path" "$repo" "$file")"
      score="$(candidate_token_score "$candidate_text" "$input")"

      if (( score > best_score )); then
        best_score=$score
        best_idx=$i
        best_tied=0
      elif (( score > 0 && score == best_score )); then
        best_tied=1
      fi
    done

    if (( best_score > 0 && best_tied == 0 && best_idx >= 0 )); then
      echo "Info: no exact token match found; using best fuzzy match (score: $best_score)." >&2
      printf "%s\n" "${MODELS[$best_idx]}"
      return 0
    fi

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
    usage_error "start requires <index|query|path>"
  fi

  require_command "$LLAMA_SERVER_CMD"

  local model_ref="$1"
  shift

  local model_path
  model_path="$(resolve_model "$model_ref")"

  local -a base_args=("-m" "$model_path")
  if autoload_mmproj_enabled && ! has_mmproj_arg "$@"; then
    local mmproj_path
    if mmproj_path="$(find_mmproj_for_model "$model_path")"; then
      base_args+=("--mmproj" "$mmproj_path")
    fi
  fi

  if autoload_mtp_enabled && ! has_model_draft_arg "$@" && ! has_spec_type_arg "$@"; then
    local mtp_path
    if mtp_path="$(find_mtp_for_model "$model_path")"; then
      base_args+=("--model-draft" "$mtp_path" "--spec-type" "draft-mtp")
      if ! has_spec_draft_n_max_arg "$@"; then
        base_args+=("--spec-draft-n-max" "$LLAMA_DEFAULT_SPEC_DRAFT_N_MAX")
      fi
    fi
  fi

  echo "Using model: $model_path"
  run_llama_tool "server" "${#base_args[@]}" "${base_args[@]}" "$@"
}

cmd_remove() {
  if [[ $# -lt 1 ]]; then
    usage_error "remove requires <index|query|path>"
  fi

  if [[ $# -gt 1 ]]; then
    usage_error "remove accepts exactly one <index|query|path> argument"
  fi

  local model_ref="$1"
  local model_path
  model_path="$(resolve_model "$model_ref")"

  local -a removal_targets=()
  local target
  while IFS= read -r target; do
    [[ -n "$target" ]] && removal_targets+=("$target")
  done < <(collect_removal_targets "$model_path")

  echo "Will remove the following path(s):"
  for target in "${removal_targets[@]}"; do
    echo "  - $target"
  done

  if ! confirm "Proceed with deletion?"; then
    return 1
  fi

  for target in "${removal_targets[@]}"; do
    if [[ -e "$target" || -L "$target" ]]; then
      rm -f -- "$target"
      echo "Removed: $target"
    else
      echo "Skipped missing path: $target" >&2
    fi
  done
}

cmd_hf() {
  if [[ $# -lt 1 ]]; then
    usage_error "hf requires <repo-id>"
  fi

  require_command "$LLAMA_SERVER_CMD"

  local repo_id="$1"
  shift

  local -a base_args=("-hf" "$repo_id")

  # Do not infer MTP support from the repo id alone. Hugging Face repos may
  # not contain a compatible mtp-*.gguf artifact, and an explicit
  # --model-draft or --spec-type must always be left untouched. Users can
  # still opt into MTP explicitly by passing the relevant llama-server flags.
  run_llama_tool "server" "${#base_args[@]}" "${base_args[@]}" "$@"
}

cmd_fit_params() {
  if [[ $# -lt 1 ]]; then
    usage_error "fit-params requires <index|query|path> or -hf <repo-id>"
  fi

  require_command "$LLAMA_FIT_PARAMS_CMD"

  local -a base_args=()
  local model_ref model_path

  case "$1" in
    -hf|--hf-repo|-hfr)
      if [[ $# -lt 2 ]]; then
        usage_error "fit-params $1 requires <repo-id>"
      fi
      base_args+=("-hf" "$2")
      echo "Using HF repo: $2"
      shift 2
      ;;
    *)
      model_ref="$1"
      shift
      model_path="$(resolve_model "$model_ref")"
      base_args+=("-m" "$model_path")
      echo "Using model: $model_path"
      ;;
  esac

  # mmproj/MTP auto-loading is intentionally omitted because llama-fit-params
  # does not accept those flags. Pass -fitp on explicitly to print the estimated
  # memory instead of the fitted CLI arguments.
  run_llama_tool "fit-params" "${#base_args[@]}" "${base_args[@]}" "$@"
}

cmd_check_updates() {
  if [[ $# -gt 0 ]]; then
    echo "Error: check-updates does not accept arguments" >&2
    echo "Usage: $SCRIPT_NAME check-updates" >&2
    return 1
  fi

  require_command curl
  collect_models

  if [[ ${#MODELS[@]} -eq 0 ]]; then
    cat <<EOF
No GGUF files found in Hugging Face cache:
  $HF_CACHE_ROOT
EOF
    return 0
  fi

  # Keep these as indexed arrays: Bash 3.2 (macOS) does not support
  # associative arrays.
  local -a repo_names=()
  local -a repo_current_commits=()
  local -a repo_file_lists=()
  local path repo commit repo_index i

  for path in "${MODELS[@]}"; do
    repo="$(model_repo_from_path "$path")"
    if [[ "$repo" == "unknown/unknown" ]]; then
      continue
    fi

    commit="${path#*/snapshots/}"
    commit="${commit%%/*}"
    repo_index=-1
    for i in "${!repo_names[@]}"; do
      if [[ "${repo_names[$i]}" == "$repo" ]]; then
        repo_index="$i"
        break
      fi
    done

    if (( repo_index < 0 )); then
      repo_names+=("$repo")
      repo_current_commits+=("$commit")
      repo_file_lists+=("$path")
    else
      repo_current_commits[$repo_index]="$commit"
      repo_file_lists[$repo_index]="${repo_file_lists[$repo_index]}"$'\n'"$path"
    fi
  done

  if [[ ${#repo_names[@]} -eq 0 ]]; then
    echo "No Hugging Face models found to check."
    return 0
  fi

  echo "Checking ${#repo_names[@]} repo(s) for updates..."
  echo

  local current_commit latest_commit file
  while IFS= read -r repo; do
    repo_index=-1
    for i in "${!repo_names[@]}"; do
      if [[ "${repo_names[$i]}" == "$repo" ]]; then
        repo_index="$i"
        break
      fi
    done
    current_commit="${repo_current_commits[$repo_index]}"
    latest_commit="$(fetch_latest_sha "$repo")"

    if [[ -z "$latest_commit" ]]; then
      printf "%s | unable to check (network error, repo not found, or private)\n" "$repo"
      continue
    fi

    if [[ "$current_commit" == "$latest_commit" ]]; then
      printf "%s | up to date (%s)\n" "$repo" "$current_commit"
    else
      printf "%s | update available\n" "$repo"
      printf "  current: %s\n" "$current_commit"
      printf "  latest:  %s\n" "$latest_commit"
    fi

    while IFS= read -r file; do
      [[ -n "$file" ]] && printf "  - %s\n" "$(basename "$file")"
    done <<< "${repo_file_lists[$repo_index]}"
  done < <(printf "%s\n" "${repo_names[@]}" | sort)
}

cmd_update() {
  if [[ $# -lt 1 ]]; then
    usage_error "update requires [--clean] <index|query|repo-id>"
  fi

  require_command "$LLAMA_SERVER_CMD"

  local clean=0
  local -a args=()
  local seen_double_dash=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --clean)
        if [[ "$seen_double_dash" == "0" ]]; then
          clean=1
        else
          args+=("$1")
        fi
        shift
        ;;
      --)
        seen_double_dash=1
        shift
        args+=("$@")
        break
        ;;
      *)
        args+=("$1")
        shift
        ;;
    esac
  done

  if [[ ${#args[@]} -lt 1 ]]; then
    usage_error "update requires <index|query|repo-id>"
  fi

  local model_ref="${args[0]}"
  local -a user_server_args=("${args[@]:1}")

  if [[ "$model_ref" == *.gguf || "$model_ref" == *.GGUF ]]; then
    echo "Error: update does not accept file paths; use a repo id, index, or query" >&2
    return 1
  fi

  local model_path
  if [[ "$model_ref" == */* ]]; then
    model_path=""
  else
    model_path="$(resolve_model "$model_ref")"
  fi

  local repo_id
  if [[ -n "$model_path" ]]; then
    repo_id="$(model_repo_from_path "$model_path")"
  else
    repo_id="$model_ref"
  fi

  if [[ "$repo_id" == "unknown/unknown" || -z "$repo_id" ]]; then
    echo "Error: could not determine repo id from: $model_ref" >&2
    return 1
  fi

  if [[ "$clean" == "1" ]]; then
    local latest_commit
    latest_commit="$(fetch_latest_sha "$repo_id")"
    if [[ -z "$latest_commit" ]]; then
      echo "Error: could not verify remote repo: $repo_id (network error, repo not found, or private)" >&2
      return 1
    fi

    collect_models

    local -a removal_targets=()
    local path
    for path in "${MODELS[@]}"; do
      if [[ "$(model_repo_from_path "$path")" == "$repo_id" ]]; then
        removal_targets+=("$path")
      fi
    done

    if [[ ${#removal_targets[@]} -eq 0 ]]; then
      echo "No cached files found for $repo_id. Proceeding to download."
    else
      echo "Will remove the following cached file(s) for $repo_id:"
      for path in "${removal_targets[@]}"; do
        echo "  - $path"
      done

      if ! confirm "Remove these files and re-download the latest version?"; then
        return 1
      fi

      for path in "${removal_targets[@]}"; do
        if [[ -e "$path" || -L "$path" ]]; then
          rm -f -- "$path"
          echo "Removed: $path"
        fi
      done
    fi
  else
    echo "Re-running llama-server -hf for $repo_id to fetch the latest version."
  fi

  local -a base_args=("-hf" "$repo_id")
  run_llama_tool "server" "${#base_args[@]}" "${base_args[@]}" "${user_server_args[@]}"
}

cmd_install() {
  if [[ $# -gt 1 ]]; then
    usage_error "install accepts at most one [target-link-path] argument"
  fi

  local source_path="$SCRIPT_PATH"
  local target_path target_dir existing_link

  target_path="$(resolve_target_path "${1:-}")"

  echo "Install source:"
  echo "  $source_path"
  echo "Install target:"
  echo "  $target_path"

  if [[ -L "$target_path" ]]; then
    existing_link="$(readlink "$target_path")"
    if link_points_to_source "$target_path" "$source_path"; then
      echo "Already installed: $target_path -> $existing_link"
      return 0
    fi

    echo "Target already exists as a symlink:"
    echo "  $target_path -> $existing_link"
    if ! confirm "Replace this existing symlink?"; then
      return 1
    fi
  elif [[ -e "$target_path" ]]; then
    if [[ -d "$target_path" ]]; then
      echo "Error: target exists and is a directory: $target_path" >&2
      return 1
    fi

    echo "Target already exists and is not a symlink:"
    echo "  $target_path"
    if ! confirm "Replace this existing file?"; then
      return 1
    fi
  else
    if ! confirm "Create this symlink?"; then
      return 1
    fi
  fi

  target_dir="$(dirname "$target_path")"
  if [[ ! -d "$target_dir" ]]; then
    echo "Creating parent directory: $target_dir"
    mkdir -p "$target_dir"
  fi

  if [[ -L "$target_path" || -f "$target_path" ]]; then
    rm -f -- "$target_path"
  fi

  if create_symlink "$source_path" "$target_path"; then
    echo "Installed: $target_path -> $source_path"
    return 0
  fi

  echo "Error: failed to create symlink: $target_path" >&2
  if is_windows_environment; then
    cat >&2 <<EOF
Windows note: symlink creation from bash may require Developer Mode or an elevated shell.
If you are using Git Bash or MSYS2, enable Developer Mode in Windows Settings or rerun from an elevated terminal.
EOF
  fi

  return 1
}

cmd_uninstall() {
  if [[ $# -gt 1 ]]; then
    usage_error "uninstall accepts at most one [target-link-path] argument"
  fi

  local source_path="$SCRIPT_PATH"
  local target_path existing_link

  target_path="$(resolve_target_path "${1:-}")"

  echo "Uninstall target:"
  echo "  $target_path"

  if [[ ! -e "$target_path" && ! -L "$target_path" ]]; then
    echo "Nothing to remove."
    return 0
  fi

  if [[ ! -L "$target_path" ]]; then
    echo "Error: target exists but is not a symlink. Refusing to remove: $target_path" >&2
    return 1
  fi

  existing_link="$(readlink "$target_path")"
  if ! link_points_to_source "$target_path" "$source_path"; then
    echo "Error: target symlink does not point to this script. Refusing to remove." >&2
    echo "  current: $existing_link" >&2
    echo "  expected: $source_path" >&2
    return 1
  fi

  if ! confirm "Remove this symlink?"; then
    return 1
  fi

  rm -f -- "$target_path"
  echo "Removed: $target_path"
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
    remove)
      shift
      cmd_remove "$@"
      ;;
    hf)
      shift
      cmd_hf "$@"
      ;;
    fit-params)
      shift
      cmd_fit_params "$@"
      ;;
    check-updates)
      shift
      cmd_check_updates "$@"
      ;;
    update)
      shift
      cmd_update "$@"
      ;;
    install)
      shift
      cmd_install "$@"
      ;;
    uninstall)
      shift
      cmd_uninstall "$@"
      ;;
    help|-h|--help)
      print_help
      ;;
    *)
      usage_error "unknown command: $cmd"
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
