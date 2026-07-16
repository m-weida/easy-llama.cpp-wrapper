# shellcheck shell=bash
# Help, validation, and interactive prompts.

print_help() {
  cat <<EOF
Usage:
  $SCRIPT_NAME list [--paths, -p]
  $SCRIPT_NAME start <index|query|/path/to/model.gguf> [llama-server args...]
  $SCRIPT_NAME remove <index|query|/path/to/model.gguf>
  $SCRIPT_NAME hf <repo-id> [llama-server args...]
  $SCRIPT_NAME fit-params <index|query|/path/to/model.gguf> [llama-fit-params args...]
  $SCRIPT_NAME fit-params -hf <repo-id>[:quant] [llama-fit-params args...]
  $SCRIPT_NAME check-updates
  $SCRIPT_NAME update [--clean] <index|query|repo-id> [llama-server args...]
  $SCRIPT_NAME install [target-link-path]
  $SCRIPT_NAME uninstall [target-link-path]
  $SCRIPT_NAME help

Commands:
  list           List downloaded GGUF models from Hugging Face cache.
                 Pass --paths (or -p) to also print each model's full path.
  start          Start llama-server with a local GGUF model.
                 Auto-loads a sibling MTP draft model (mtp-*.gguf) when found,
                 using --model-draft <mtp> --spec-type draft-mtp
                 --spec-draft-n-max $LLAMA_DEFAULT_SPEC_DRAFT_N_MAX.
  remove         Preview and remove a local GGUF model plus safe associated files.
  hf             Start llama-server directly from a Hugging Face repo via -hf.
                 MTP remains opt-in because not every repo provides a compatible draft model.
  fit-params     Test whether a model fits in device memory via llama-fit-params.
                 Prints the fitted CLI arguments (-c/-ngl chosen by --fit) by
                 default; append -fitp on to print the estimated memory
                 (model/context/compute) per device instead.
                 Applies the same -ctk/-ctv/-np/-fa defaults as start/hf;
                 mmproj/MTP are not auto-loaded because llama-fit-params does
                 not accept them.
  check-updates  Check cached Hugging Face repos for newer commits on the
                 default branch and report which models have updates.
  update         Re-run llama-server -hf for a repo to fetch the latest version.
                 Pass --clean to delete the old cached files first.
  install        Create a symlink to this script after confirming the target path.
  uninstall      Remove the symlink created by install after confirming it points here.
  help           Show this help.

Default llama-server flags (added for start/hf unless overridden):
  -ctk $LLAMA_DEFAULT_CTK, -ctv $LLAMA_DEFAULT_CTV,
  -np $LLAMA_DEFAULT_NP, -fa $LLAMA_DEFAULT_FA

--jinja is enabled by default in llama-server, so the wrapper does not add it;
pass --no-jinja to opt out. -ngl is not added either; --fit (on by default)
tunes it to fit device memory, so pass -ngl explicitly to pin a value.
fit-params applies the same -ctk/-ctv/-np/-fa defaults but omits --tools,
which llama-fit-params does not support.

Examples:
  $SCRIPT_NAME list
  $SCRIPT_NAME list --paths
  $SCRIPT_NAME start 1
  $SCRIPT_NAME start gemma-4-E4B-it-Q4_K_M
  $SCRIPT_NAME start ~/models/mistral.gguf --port 8080
  LLAMA_ENABLE_TOOLS=0 $SCRIPT_NAME start 1
  LLAMA_DEFAULT_TOOLS=all $SCRIPT_NAME start 1
  $SCRIPT_NAME remove 1
  $SCRIPT_NAME hf ggml-org/gemma-4-e4b-it-GGUF --port 8080
  $SCRIPT_NAME fit-params 1
  $SCRIPT_NAME fit-params gemma-4-E4B-it-Q4_K_M
  $SCRIPT_NAME fit-params -hf unsloth/Qwen3.6-27B-MTP-GGUF:UD-Q4_K_XL
  $SCRIPT_NAME fit-params 1 -c 32768 -fit off
  $SCRIPT_NAME check-updates
  $SCRIPT_NAME update 1
  $SCRIPT_NAME update unsloth/gemma-4-12B-it-qat-GGUF
  $SCRIPT_NAME update --clean 1
  $SCRIPT_NAME install
  $SCRIPT_NAME install ~/bin/llama-models
  $SCRIPT_NAME uninstall

Config (optional env vars):
  LLAMA_SERVER_CMD  Command to run llama server (default: llama-server)
  LLAMA_FIT_PARAMS_CMD
                    Command to run llama-fit-params (default: llama-fit-params)
  LLAMA_ENABLE_TOOLS
                    Enable default tools; set to 0/false/no/off to opt out
  LLAMA_DEFAULT_TOOLS
                    Default --tools value (default: read_file,file_glob_search,
                    grep_search,get_datetime; set to all to opt in to all tools)
  LLAMA_DEFAULT_CTK Default value for -ctk (default: q8_0)
  LLAMA_DEFAULT_CTV Default value for -ctv (default: q8_0)
  LLAMA_DEFAULT_NP  Default value for -np (default: 1)
  LLAMA_DEFAULT_FA  Default value for -fa (default: on)
  LLAMA_AUTO_MTP    Auto-load MTP draft models for supported models (default: 1)
  LLAMA_DEFAULT_SPEC_DRAFT_N_MAX
                    Default value for --spec-draft-n-max (default: 2)
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

usage_error() {
  echo "Error: $1" >&2
  print_help
  exit 1
}
