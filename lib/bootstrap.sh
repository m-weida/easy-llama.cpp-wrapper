# shellcheck shell=bash
# Bootstrap and configuration.

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

SCRIPT_PATH="$(resolve_physical_path "${SCRIPT_PATH:-${BASH_SOURCE[0]}}")"
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
