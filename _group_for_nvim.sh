#!/bin/bash

set -e
JQ="${JQ:-$(which jq)}"
set +e

exec $JQ '. | group_by(.file) | map({key: .[0].file, value: (. | map(del(.file)))}) | from_entries'
