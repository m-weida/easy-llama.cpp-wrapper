# shellcheck shell=bash
# Commands that operate on local or remote models.

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
