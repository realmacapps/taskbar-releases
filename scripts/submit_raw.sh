#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

if [[ $# -ne 1 ]]; then
  echo "Usage: submit_raw.sh /path/to/raw.zip" >&2
  exit 2
fi

src_zip="$1"
if [[ ! -f "${src_zip}" ]]; then
  echo "File not found: ${src_zip}" >&2
  exit 2
fi

mkdir -p releases/raw

base="$(basename "${src_zip}")"
dest="releases/raw/${base}"

if [[ -e "${dest}" ]]; then
  stamp="$(date +%Y%m%d-%H%M%S)"
  dest="releases/raw/${stamp}-${base}"
fi

cp "${src_zip}" "${dest}"
git add "${dest}"
git commit -m "Add raw artifact $(basename "${dest}")"
git push origin main

echo "Submitted raw artifact: ${dest}"
