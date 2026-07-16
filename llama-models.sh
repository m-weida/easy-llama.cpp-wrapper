#!/usr/bin/env bash
set -euo pipefail

# Resolve the entrypoint before sourcing modules so the installed symlink
# works regardless of the caller's current working directory.
SCRIPT_ENTRYPOINT="${BASH_SOURCE[0]}"
SCRIPT_PATH="$SCRIPT_ENTRYPOINT"
while [[ -L "$SCRIPT_PATH" ]]; do
  link_target="$(readlink "$SCRIPT_PATH")"
  if [[ "$link_target" == /* ]]; then
    SCRIPT_PATH="$link_target"
  else
    SCRIPT_PATH="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd -P)/$link_target"
  fi
done
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd -P)"

source "$SCRIPT_DIR/lib/bootstrap.sh"
source "$SCRIPT_DIR/lib/ui.sh"
source "$SCRIPT_DIR/lib/paths.sh"
source "$SCRIPT_DIR/lib/llama.sh"
source "$SCRIPT_DIR/lib/attachments.sh"
source "$SCRIPT_DIR/lib/models.sh"
source "$SCRIPT_DIR/lib/commands-models.sh"
source "$SCRIPT_DIR/lib/commands-updates.sh"
source "$SCRIPT_DIR/lib/commands-install.sh"
source "$SCRIPT_DIR/lib/dispatch.sh"

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
