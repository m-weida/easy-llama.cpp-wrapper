# shellcheck shell=bash
# Hugging Face cache discovery and model resolution.

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
