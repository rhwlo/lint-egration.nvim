#!/bin/bash

DEFAULT_FLAKE8="uvx flake8"

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
