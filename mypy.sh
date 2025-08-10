#!/bin/bash

DEFAULT_MYPY="uvx mypy"
set -e
JQ="${JQ:-$(which jq)}"
MYPY="${MYPY:-$DEFAULT_MYPY}"
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

$MYPY --output json "$@" | jq --slurp "$JQ_FILTER"
