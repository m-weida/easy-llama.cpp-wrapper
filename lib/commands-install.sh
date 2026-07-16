# shellcheck shell=bash
# Install and uninstall commands.

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
