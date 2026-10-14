#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
output=${1:?Usage: bash scripts/linux/run.sh OUTPUT_DIRECTORY}
mkdir -p "$output"
output=$(cd "$output" && pwd)
# Git Bash requires Windows paths for bind mounts, and no argument rewriting.
if command -v cygpath >/dev/null 2>&1; then
    repo=$(cygpath -m "$repo")
    output=$(cygpath -m "$output")
fi
docker info >/dev/null
docker build -t south-plus-linux-e2e -f "$repo/scripts/linux/Dockerfile" "$repo/scripts/linux"
MSYS_NO_PATHCONV=1 docker run --rm \
    --mount "type=bind,source=$repo,target=/source,readonly" \
    --mount "type=bind,source=$output,target=/output" \
    --mount type=volume,source=spp-pub-cache,target=/root/.pub-cache \
    south-plus-linux-e2e
