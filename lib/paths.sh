# shellcheck shell=bash
# Cross-platform paths and symlink operations.

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
