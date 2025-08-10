#!/bin/bash

USE_DMYPY=1

if grep -q 'name = "mypy"' poetry.lock 2>/dev/null; then
  # if there's a poetry mypy, then use that
  DEFAULT_PREFIX="poetry run "
elif grep -q 'name = "mypy"' uv.lock 2>/dev/null; then
  # if there's a uv mypy, then use that
  DEFAULT_PREFIX="uv run "
elif [ -x .venv/bin/mypy ]; then
  # if there's a virtualenv mypy, then use that
  DEFAULT_PREFIX="./.venv/bin/"
elif which mypy | grep -vq " not found"; then
  # if there's a mypy in our path, then use that
  DEFAULT_PREFIX=""
else
  # otherwise, use mypy via uvx; use --from=mypy so that this works for dmypy too
  DEFAULT_PREFIX="uvx --from=mypy "
fi
DEFAULT_MYPY="${DEFAULT_PREFIX}mypy"
DEFAULT_DMYPY="${DEFAULT_PREFIX}dmypy"

set -e
JQ="${JQ:-$(which jq)}"
MYPY="${MYPY:-$DEFAULT_MYPY}"
DMYPY="${DMYPY:-$DEFAULT_DMYPY}"
set +e

JQ_FILTER='map(
  del(.hint) +
  {
    severity: ({"w": "WARNING", "i": "INFO", "h": "HINT" }[.severity[0:1]] // "ERROR"),
    lnum: (.line - 1),
    col: .column,
    source: "mypy"
  }
) | group_by(.file)
  | map({key: .[0].file, value: (. | map(del(.file)))})
  | from_entries
'

if [ -z "$USE_DMYPY" ]; then
  $MYPY --output json "$@" 2>/dev/null | jq --slurp "$JQ_FILTER"
else
  $DMYPY run --timeout 600 -- --output=json "$@" 2>/dev/null | grep -v '^Daemon ' | jq --slurp "$JQ_FILTER"
fi
