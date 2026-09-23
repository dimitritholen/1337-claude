#!/usr/bin/env bash
# The eval runs in an empty temp dir; give it the style file the prompt names.
set -euo pipefail
mkdir -p output-styles
cp "$(cd "$(dirname "$0")/../.." && pwd)/output-styles/unc.md" output-styles/unc.md
