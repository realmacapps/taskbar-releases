#!/usr/bin/env bash
set -euo pipefail

SPARKLE_VERSION="${SPARKLE_VERSION:-2.8.1}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS_ROOT="${ROOT_DIR}/build/sparkle-tools"
TOOLS_DIR="${TOOLS_ROOT}/Sparkle-${SPARKLE_VERSION}"
TARBALL="${TOOLS_ROOT}/Sparkle-${SPARKLE_VERSION}.tar.xz"

if [[ ! -x "${TOOLS_DIR}/bin/sign_update" ]]; then
  mkdir -p "${TOOLS_ROOT}"
  curl -L -o "${TARBALL}" "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
  rm -rf "${TOOLS_DIR}"
  mkdir -p "${TOOLS_DIR}"
  tar -xJf "${TARBALL}" -C "${TOOLS_DIR}" --strip-components=1
fi

echo "${TOOLS_DIR}/bin"
