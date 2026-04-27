# custom-llama-sh

Small helper script for `llama.cpp` (`llama-server`) on macOS/Linux.

## What it does

- Lists locally cached Hugging Face GGUF models
- Starts a local GGUF model with `-ngl 99` by default
- Starts directly from Hugging Face via `-hf`

Script: `./llama-models.sh`

## Requirements

- `llama-server` available in your `PATH`
- Hugging Face cache present (usually `~/.cache/huggingface/hub`)

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

Start directly from HF repo:

```bash
./llama-models.sh hf ggml-org/gemma-4-e4b-it-GGUF --port 8080
```

## Optional environment variables

- `LLAMA_SERVER_CMD` (default: `llama-server`)
- `NGL_DEFAULT` (default: `99`)
- `HF_HUB_CACHE` (explicit HF hub cache path)
- `HF_HOME` (uses `$HF_HOME/hub`)

Example:

```bash
NGL_DEFAULT=60 ./llama-models.sh start 1
```
