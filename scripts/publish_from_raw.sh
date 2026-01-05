#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

RAW_DIR="${RAW_DIR:-releases/raw}"

if [[ -z "${GITHUB_REPOSITORY:-}" ]]; then
  echo "Missing GITHUB_REPOSITORY env var (expected in GitHub Actions)." >&2
  exit 1
fi

if [[ -z "${SPARKLE_ED25519_PRIVATE_KEY:-}" ]]; then
  echo "Missing SPARKLE_ED25519_PRIVATE_KEY secret." >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "Missing gh CLI (this script is intended to run in GitHub Actions (macos runner))." >&2
  exit 1
fi

if [[ ! -d "${RAW_DIR}" ]]; then
  echo "Raw directory not found: ${RAW_DIR}" >&2
  exit 1
fi

RAW_FILES=()
while IFS= read -r raw_file; do
  [[ -n "${raw_file}" ]] || continue
  RAW_FILES+=("${raw_file}")
done < <(find "${RAW_DIR}" -maxdepth 1 -type f -name "*.zip" -print | sort)
if [[ ${#RAW_FILES[@]} -eq 0 ]]; then
  echo "No raw .zip artifacts found in ${RAW_DIR}"
  exit 0
fi

SPARKLE_BIN_DIR="$("${ROOT_DIR}/scripts/fetch_sparkle_tools.sh")"
SIGN_UPDATE_BIN="${SPARKLE_BIN_DIR}/sign_update"

if [[ ! -x "${SIGN_UPDATE_BIN}" ]]; then
  echo "Sparkle sign_update not found at: ${SIGN_UPDATE_BIN}" >&2
  exit 1
fi

processed_count=0
last_title=""

for raw_zip in "${RAW_FILES[@]}"; do
  tmpdir="$(mktemp -d)"
  extracted_dir="${tmpdir}/extracted"
  mkdir -p "${extracted_dir}"

  if ! ditto -x -k "${raw_zip}" "${extracted_dir}" >/dev/null 2>&1; then
    echo "Failed to extract raw zip: ${raw_zip}" >&2
    rm -rf "${tmpdir}"
    exit 1
  fi

  app_path="$(find "${extracted_dir}" -maxdepth 6 -type d -name "*.app" -print -quit)"
  if [[ -z "${app_path}" ]]; then
    xcarchive_path="$(find "${extracted_dir}" -maxdepth 6 -type d -name "*.xcarchive" -print -quit)"
    if [[ -n "${xcarchive_path}" ]]; then
      app_path="$(find "${xcarchive_path}/Products/Applications" -maxdepth 1 -type d -name "*.app" -print -quit)"
    fi
  fi

  if [[ -z "${app_path}" ]]; then
    echo "No .app found inside raw zip: ${raw_zip}" >&2
    rm -rf "${tmpdir}"
    exit 1
  fi

  info_plist="${app_path}/Contents/Info.plist"
  if [[ ! -f "${info_plist}" ]]; then
    echo "Missing Info.plist at: ${info_plist}" >&2
    rm -rf "${tmpdir}"
    exit 1
  fi

  short_version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${info_plist}")"
  build_version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "${info_plist}")"
  min_os="$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "${info_plist}" 2>/dev/null || true)"
  if [[ -z "${min_os}" ]]; then
    min_os="15.0"
  fi

  app_name="$(/usr/libexec/PlistBuddy -c "Print :CFBundleName" "${info_plist}" 2>/dev/null || true)"
  if [[ -z "${app_name}" ]]; then
    app_name="$(basename "${app_path}" .app)"
  fi

  safe_app_name="$(echo "${app_name}" | tr " " "-" | tr -cd "A-Za-z0-9._-")"
  if [[ -z "${safe_app_name}" ]]; then
    safe_app_name="App"
  fi

  tag="v${short_version}-${build_version}"
  title="${app_name} ${short_version} (${build_version})"
  notes="Build ${build_version}"

  update_zip="${tmpdir}/${safe_app_name}-${short_version}-${build_version}.zip"
  dmg_path="${tmpdir}/${safe_app_name}-${short_version}-${build_version}.dmg"

  ditto -c -k --sequesterRsrc --keepParent "${app_path}" "${update_zip}" >/dev/null 2>&1
  hdiutil create -volname "${app_name}" -srcfolder "${app_path}" -ov -format UDZO "${dmg_path}" >/dev/null 2>&1

  key_file="${tmpdir}/sparkle_ed25519.key"
  printf "%s" "${SPARKLE_ED25519_PRIVATE_KEY}" > "${key_file}"
  chmod 600 "${key_file}"

  sign_output="$("${SIGN_UPDATE_BIN}" --ed-key-file "${key_file}" "${update_zip}" 2>/dev/null | tr -d '\n')"
  signature=""
  if [[ "${sign_output}" == *'sparkle:edSignature="'* ]]; then
    signature="${sign_output#*sparkle:edSignature=\"}"
    signature="${signature%%\"*}"
  fi
  if [[ -z "${signature}" ]]; then
    echo "Failed to compute Sparkle signature for: ${update_zip}" >&2
    echo "sign_update output: ${sign_output}" >&2
    rm -rf "${tmpdir}"
    exit 1
  fi

  length="$(stat -f%z "${update_zip}")"
  pub_date="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S %z')"

  if gh release view "${tag}" --repo "${GITHUB_REPOSITORY}" >/dev/null 2>&1; then
    gh release upload "${tag}" "${update_zip}" "${dmg_path}" --clobber --repo "${GITHUB_REPOSITORY}"
    gh release edit "${tag}" --title "${title}" --notes "${notes}" --repo "${GITHUB_REPOSITORY}"
  else
    gh release create "${tag}" "${update_zip}" "${dmg_path}" --title "${title}" --notes "${notes}" --latest --repo "${GITHUB_REPOSITORY}"
  fi

  download_url="https://github.com/${GITHUB_REPOSITORY}/releases/download/${tag}/$(basename "${update_zip}")"
  release_notes_url="https://github.com/${GITHUB_REPOSITORY}/releases/tag/${tag}"

  ruby "${ROOT_DIR}/scripts/update_appcast.rb" \
    --appcast "${ROOT_DIR}/appcast.xml" \
    --title "${title}" \
    --short-version "${short_version}" \
    --build "${build_version}" \
    --pub-date "${pub_date}" \
    --url "${download_url}" \
    --length "${length}" \
    --signature "${signature}" \
    --min-os "${min_os}" \
    --release-notes-url "${release_notes_url}"

  git add "${ROOT_DIR}/appcast.xml"
  git rm -f --ignore-unmatch "${raw_zip}"

  processed_count=$((processed_count + 1))
  last_title="${title}"

  rm -rf "${tmpdir}"
done

if git diff --cached --quiet; then
  echo "No repository changes to commit."
  exit 0
fi

commit_message="Publish updates"
if [[ ${processed_count} -eq 1 && -n "${last_title}" ]]; then
  commit_message="Publish ${last_title}"
fi

git commit -m "${commit_message}"
git push origin HEAD:main
