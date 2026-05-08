# custom-llama-sh

Small helper script for `llama.cpp` (`llama-server`) for bash-compatible shells on macOS, Linux, and Windows.

## What it does

- Lists locally cached Hugging Face GGUF models
- Starts a local GGUF model with `-ngl 99` by default
- Starts directly from Hugging Face via `-hf`
- Adds `--jinja` by default for `start` and `hf`
- Enables a safe built-in tool subset by default
- Auto-loads a sibling `mmproj` file for `start` when one is found
- Can preview and remove a cached model with a confirmation prompt

Script: `./llama-models.sh`

## Requirements

- `llama-server` available in your `PATH`
- Hugging Face cache present (usually `~/.cache/huggingface/hub`)
- A bash-compatible shell

Windows notes:

- Run the script from Git Bash, MSYS2, Cygwin, or WSL.
- `install` creates a symlink, which may require Windows Developer Mode or an elevated shell.

## Install / uninstall

Create a symlink in your home directory after confirming the target path:

```bash
./llama-models.sh install
```

By default this installs to `~/llama-models.sh`.

Use a custom symlink path if you prefer:

```bash
./llama-models.sh install ~/bin/llama-models
```

Remove the symlink later:

```bash
./llama-models.sh uninstall
```

Or remove a custom symlink path:

```bash
./llama-models.sh uninstall ~/bin/llama-models
```

`install` always prints the resolved source and target first, then asks for confirmation before creating or replacing anything.
`uninstall` only removes a symlink when it points back to this repo's script, and asks for confirmation before deleting it.

## Usage

Show help:

```bash
./llama-models.sh help
```

List downloaded models:

```bash
./llama-models.sh list
```

Start by index from list:

```bash
./llama-models.sh start 1
```

Preview and remove by index:

```bash
./llama-models.sh remove 1
```

Start by search query:

```bash
./llama-models.sh start gemma-4-E4B-it-Q4_K_M
```

Start from explicit file path:

```bash
./llama-models.sh start ~/models/my-model.gguf
```

Pass extra `llama-server` args:

```bash
./llama-models.sh start 1 --port 8080 --ctx-size 8192
```

The wrapper adds `--jinja` automatically for both `start` and `hf` unless you already pass it yourself.

You can disable that default with:

```bash
LLAMA_AUTO_JINJA=0 ./llama-models.sh start 1
```

The wrapper also adds this safe default tool set for both `start` and `hf`:

```text
read_file,file_glob_search,grep_search,get_datetime
```

Opt out entirely by setting:

```bash
LLAMA_ENABLE_TOOLS=0 ./llama-models.sh start 1
```

Opt in to all built-in tools by setting:

```bash
LLAMA_DEFAULT_TOOLS=all ./llama-models.sh start 1
```

If a matching `mmproj` file is next to the resolved model, `start` adds it automatically.
If you already pass `--mmproj`, the script leaves it alone.

`remove` prints the exact paths it will delete, then asks for confirmation before removing anything. The prompt defaults to `y/N`, so pressing Enter aborts the deletion.

You can disable automatic `mmproj` loading with:

```bash
LLAMA_AUTO_MMPROJ=0 ./llama-models.sh start 1
```

Start directly from HF repo:

```bash
./llama-models.sh hf ggml-org/gemma-4-e4b-it-GGUF --port 8080
```

## Quantization selection

When using `hf`, append `:<QUANT>` to the repo id:

```bash
./llama-models.sh hf ggml-org/gemma-4-e4b-it-GGUF:Q5_K_M
```

Notes:

- Quant names are case-insensitive in `llama-server`.
- If you do not provide a quant, `llama-server` chooses its default (typically `Q4_K_M`).
- To force an exact filename from a repo, pass `--hf-file`:

```bash
./llama-models.sh hf ggml-org/gemma-4-e4b-it-GGUF --hf-file gemma-4-E4B-it-Q4_K_M.gguf
```

If the model is already cached locally, `start` can match by query text:

```bash
./llama-models.sh start Q5_K_M
```

You can also provide multiple terms (space-separated, order-independent):

```bash
./llama-models.sh start "Q5_K_M gemma 4"
```

If no exact token match exists, the script can fall back to the unique best local match.
Example: if only `Q4_K_M` is cached, querying `Q5_K_M gemma 4` will pick that `Q4_K_M` model.

## Optional environment variables

- `LLAMA_SERVER_CMD` (default: `llama-server`)
- `NGL_DEFAULT` (default: `99`)
- `LLAMA_AUTO_JINJA` (default: `1`; set `0`, `false`, `no`, or `off` to opt out)
- `LLAMA_ENABLE_TOOLS` (default: `1`; set `0`, `false`, `no`, or `off` to opt out)
- `LLAMA_DEFAULT_TOOLS` (default: `read_file,file_glob_search,grep_search,get_datetime`; set `all` to opt in to all tools)
- `LLAMA_AUTO_MMPROJ` (default: `1`)
- `HF_HUB_CACHE` (explicit HF hub cache path)
- `HF_HOME` (uses `$HF_HOME/hub`)

Example:

```bash
NGL_DEFAULT=60 ./llama-models.sh start 1
```
