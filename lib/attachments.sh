# shellcheck shell=bash
# Automatic mmproj and MTP attachment discovery.

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
