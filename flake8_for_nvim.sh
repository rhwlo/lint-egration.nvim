#!/bin/bash

if grep -q 'name = "flake8"' poetry.lock 2>/dev/null; then
  # if there's a poetry flake8, then use that
  DEFAULT_PREFIX="poetry run "
elif grep -q 'name = "flake8"' uv.lock 2>/dev/null; then
  # if there's a uv flake8, then use that
  DEFAULT_PREFIX="uv run "
elif [ -x .venv/bin/flake8 ]; then
  # if there's a virtualenv flake8, then use that
  DEFAULT_PREFIX="./.venv/bin/"
elif which flake8 | grep -vq " not found"; then
  # if there's a flake8 on our path, use that
  DEFAULT_PREFIX=""
else
  # otherwise, use flake8 via uvx
  DEFAULT_PREFIX="uvx "
fi
DEFAULT_FLAKE8="${DEFAULT_PREFIX}flake8"

set -e
JQ="${JQ:-$(which jq)}"
FLAKE8="${FLAKE8:-$DEFAULT_FLAKE8}"
set +e

FLAKE8_FORMAT_STRING='{"file":"%(path)s","col":%(col)s,"lnum":%(row)s,"code":"%(code)s","message":"[%(code)s] %(text)s","source":"flake8"}'

JQ_FILTER='map(
  . + {
    severity: ({ "W": "WARN", "I": "INFO" }[.code[0:1]] // "ERROR"),
    col: (.col - 1),
    lnum: (.lnum - 1)
  }
) | group_by(.file)
| map({key: .[0].file, value: (. | map(del(.file)))})
| from_entries'
$FLAKE8 --format="$FLAKE8_FORMAT_STRING" "$@" | jq --slurp "$JQ_FILTER"
