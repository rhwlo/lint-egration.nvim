#!/bin/bash

DEFAULT_MYPY="uvx mypy"
set -e
JQ="${JQ:-$(which jq)}"
MYPY="${MYPY:-$DEFAULT_MYPY}"
set +e

$MYPY --output json "$@" | jq --slurp 'map(del(.hint) + {severity: .severity[0:1] | ascii_upcase}) | group_by(.file) | map({key: .[0].file, value: (. | map(del(.file)))}) | from_entries'
