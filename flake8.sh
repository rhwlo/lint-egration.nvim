#!/bin/bash

DEFAULT_FLAKE8="uvx flake8"

set -e
JQ="${JQ:-$(which jq)}"
FLAKE8="${FLAKE8:-$DEFAULT_FLAKE8}"
set +e

FLAKE8_FORMAT_STRING='{"file":"%(path)s","column":%(col)s,"line":%(row)s,"code":"%(code)s","message":"[%(code)s] %(text)s"}'

$FLAKE8 --format="$FLAKE8_FORMAT_STRING" "$@" | jq --slurp 'map(. + {severity: .severity[0:1]}) | group_by(.file) | map({key: .[0].file, value: (. | map(del(.file)))}) | from_entries'
