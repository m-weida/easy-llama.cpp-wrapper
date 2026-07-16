# shellcheck shell=bash
# Hugging Face update checking and refresh commands.

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
      repo_current_commits[repo_index]="$commit"
      repo_file_lists[repo_index]="${repo_file_lists[$repo_index]}"$'\n'"$path"
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
