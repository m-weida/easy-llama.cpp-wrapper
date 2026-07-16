# shellcheck shell=bash
# Argument matching and llama.cpp command execution.

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
