#!/usr/bin/env bash
set -euo pipefail

archive="$1"
expected="$2"

if [[ -z "${expected}" ]]; then
  exit 0
fi

echo "${expected}  ${archive}" | sha256sum -c -
