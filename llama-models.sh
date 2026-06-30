#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

resolve_physical_path() {
  local path="$1"
  local link_target dir

  path="${path/#\~/$HOME}"

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
NGL_DEFAULT="${NGL_DEFAULT:-99}"
LLAMA_AUTO_MMPROJ="${LLAMA_AUTO_MMPROJ:-1}"
LLAMA_AUTO_JINJA="${LLAMA_AUTO_JINJA:-1}"
LLAMA_ENABLE_TOOLS="${LLAMA_ENABLE_TOOLS:-1}"
LLAMA_DEFAULT_TOOLS="${LLAMA_DEFAULT_TOOLS:-read_file,file_glob_search,grep_search,get_datetime}"
LLAMA_DEFAULT_CTK="${LLAMA_DEFAULT_CTK:-q8_0}"
LLAMA_DEFAULT_CTV="${LLAMA_DEFAULT_CTV:-q4_1}"
LLAMA_DEFAULT_NP="${LLAMA_DEFAULT_NP:-1}"
LLAMA_DEFAULT_FA="${LLAMA_DEFAULT_FA:-on}"

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
  $SCRIPT_NAME remove <index|query|/path/to/model.gguf>
  $SCRIPT_NAME hf <repo-id> [llama-server args...]
  $SCRIPT_NAME install [target-link-path]
  $SCRIPT_NAME uninstall [target-link-path]
  $SCRIPT_NAME help

Commands:
  list    List downloaded GGUF models from Hugging Face cache.
  start   Start llama-server with a local GGUF model, -ngl $NGL_DEFAULT,
    --jinja, -ctk $LLAMA_DEFAULT_CTK, -ctv $LLAMA_DEFAULT_CTV,
    -np $LLAMA_DEFAULT_NP and -fa $LLAMA_DEFAULT_FA by default.
  remove  Preview and remove a local GGUF model plus safe associated files.
  hf      Start llama-server directly from a Hugging Face repo via -hf
    with -ngl $NGL_DEFAULT, --jinja, -ctk $LLAMA_DEFAULT_CTK, -ctv $LLAMA_DEFAULT_CTV,
    -np $LLAMA_DEFAULT_NP and -fa $LLAMA_DEFAULT_FA by default.
  install Create a symlink to this script after confirming the target path.
  uninstall
          Remove the symlink created by install after confirming it points here.
  help    Show this help.

Examples:
  $SCRIPT_NAME list
  $SCRIPT_NAME start 1
  $SCRIPT_NAME start gemma-4-E4B-it-Q4_K_M
  $SCRIPT_NAME start ~/models/mistral.gguf --port 8080
  LLAMA_ENABLE_TOOLS=0 $SCRIPT_NAME start 1
  LLAMA_DEFAULT_TOOLS=all $SCRIPT_NAME start 1
  $SCRIPT_NAME remove 1
  $SCRIPT_NAME hf ggml-org/gemma-4-e4b-it-GGUF --port 8080
  $SCRIPT_NAME install
  $SCRIPT_NAME install ~/bin/llama-models
  $SCRIPT_NAME uninstall

Config (optional env vars):
  LLAMA_SERVER_CMD  Command to run llama server (default: llama-server)
  NGL_DEFAULT       Default value for -ngl (default: 99)
  LLAMA_AUTO_JINJA  Add --jinja by default; set to 0/false/no/off to opt out
  LLAMA_ENABLE_TOOLS
                    Enable default tools; set to 0/false/no/off to opt out
  LLAMA_DEFAULT_TOOLS
                    Default --tools value (default: read_file,file_glob_search,
                    grep_search,get_datetime; set to all to opt in to all tools)
  LLAMA_DEFAULT_CTK Default value for -ctk (default: q8_0)
  LLAMA_DEFAULT_CTV Default value for -ctv (default: q4_1)
  LLAMA_DEFAULT_NP  Default value for -np (default: 1)
  LLAMA_DEFAULT_FA  Default value for -fa (default: on)
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

default_install_target() {
  printf "%s\n" "$HOME/llama-models.sh"
}

resolve_target_path() {
  local input="${1:-$(default_install_target)}"

  input="${input/#\~/$HOME}"

  if [[ "$input" != /* ]]; then
    printf "%s\n" "$PWD/$input"
    return
  fi

  printf "%s\n" "$input"
}

confirm_action() {
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

autoload_jinja_enabled() {
  case "$LLAMA_AUTO_JINJA" in
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

has_jinja_arg() {
  local arg

  for arg in "$@"; do
    case "$arg" in
      --jinja)
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

default_tools_value() {
  printf "%s\n" "$LLAMA_DEFAULT_TOOLS"
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

collect_removal_targets() {
  local model_path="$1"
  local -a targets=("$model_path")
  local mmproj_path

  if mmproj_path="$(find_mmproj_for_model "$model_path")"; then
    if mmproj_is_shared "$mmproj_path" "$model_path"; then
      echo "Info: mmproj is shared with other model(s), keeping: $mmproj_path" >&2
    else
      targets+=("$mmproj_path")
    fi
  fi

  printf "%s\n" "${targets[@]}"
}

confirm_removal() {
  local response

  printf "Proceed with deletion? [y/N] "
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
    # skip GGUF files that were generated from .mmproj exports
    # (they often include the substring 'mmproj' in the filename)
    if [[ "$(basename "$path")" == *mmproj* ]]; then
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
    echo "Error: start requires <index|query|path>" >&2
    print_help
    exit 1
  fi

  require_command "$LLAMA_SERVER_CMD"

  local model_ref="$1"
  shift

  local model_path
  model_path="$(resolve_model "$model_ref")"

  local -a server_args=("-m" "$model_path" "-ngl" "$NGL_DEFAULT")
  if autoload_jinja_enabled && ! has_jinja_arg "$@"; then
    server_args+=("--jinja")
  fi
  if tools_enabled && ! has_tools_arg "$@"; then
    server_args+=("--tools" "$(default_tools_value)")
  fi
  if autoload_mmproj_enabled && ! has_mmproj_arg "$@"; then
    local mmproj_path
    if mmproj_path="$(find_mmproj_for_model "$model_path")"; then
      server_args+=("--mmproj" "$mmproj_path")
    fi
  fi
  if ! has_ctk_arg "$@"; then
    server_args+=("-ctk" "$LLAMA_DEFAULT_CTK")
  fi
  if ! has_ctv_arg "$@"; then
    server_args+=("-ctv" "$LLAMA_DEFAULT_CTV")
  fi
  if ! has_np_arg "$@"; then
    server_args+=("-np" "$LLAMA_DEFAULT_NP")
  fi
  if ! has_fa_arg "$@"; then
    server_args+=("-fa" "$LLAMA_DEFAULT_FA")
  fi

  if [[ $# -gt 0 ]]; then
    server_args+=("$@")
  fi

  echo "Using model: $model_path"
  echo "Running: $LLAMA_SERVER_CMD ${server_args[*]}"

  "$LLAMA_SERVER_CMD" "${server_args[@]}"
}

cmd_remove() {
  if [[ $# -lt 1 ]]; then
    echo "Error: remove requires <index|query|path>" >&2
    print_help
    exit 1
  fi

  if [[ $# -gt 1 ]]; then
    echo "Error: remove accepts exactly one <index|query|path> argument" >&2
    print_help
    exit 1
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

  if ! confirm_removal; then
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
    echo "Error: hf requires <repo-id>" >&2
    print_help
    exit 1
  fi

  require_command "$LLAMA_SERVER_CMD"

  local repo_id="$1"
  shift

  local -a server_args=("-hf" "$repo_id" "-ngl" "$NGL_DEFAULT")
  if autoload_jinja_enabled && ! has_jinja_arg "$@"; then
    server_args+=("--jinja")
  fi
  if tools_enabled && ! has_tools_arg "$@"; then
    server_args+=("--tools" "$(default_tools_value)")
  fi
  if ! has_ctk_arg "$@"; then
    server_args+=("-ctk" "$LLAMA_DEFAULT_CTK")
  fi
  if ! has_ctv_arg "$@"; then
    server_args+=("-ctv" "$LLAMA_DEFAULT_CTV")
  fi
  if ! has_np_arg "$@"; then
    server_args+=("-np" "$LLAMA_DEFAULT_NP")
  fi
  if ! has_fa_arg "$@"; then
    server_args+=("-fa" "$LLAMA_DEFAULT_FA")
  fi
  if [[ $# -gt 0 ]]; then
    server_args+=("$@")
  fi

  echo "Running: $LLAMA_SERVER_CMD ${server_args[*]}"
  "$LLAMA_SERVER_CMD" "${server_args[@]}"
}

cmd_install() {
  if [[ $# -gt 1 ]]; then
    echo "Error: install accepts at most one [target-link-path] argument" >&2
    print_help
    exit 1
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
    if ! confirm_action "Replace this existing symlink?"; then
      return 1
    fi
  elif [[ -e "$target_path" ]]; then
    if [[ -d "$target_path" ]]; then
      echo "Error: target exists and is a directory: $target_path" >&2
      return 1
    fi

    echo "Target already exists and is not a symlink:"
    echo "  $target_path"
    if ! confirm_action "Replace this existing file?"; then
      return 1
    fi
  else
    if ! confirm_action "Create this symlink?"; then
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
    echo "Error: uninstall accepts at most one [target-link-path] argument" >&2
    print_help
    exit 1
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

  if ! confirm_action "Remove this symlink?"; then
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
      echo "Error: unknown command: $cmd" >&2
      print_help
      exit 1
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
