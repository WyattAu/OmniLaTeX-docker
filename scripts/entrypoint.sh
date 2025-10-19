#!/usr/bin/env bash
set -euo pipefail

if [[ "${SET_ENTRYPOINT:-true}" == "true" ]]; then
  exec latexmk "$@"
fi

exec "$@"
