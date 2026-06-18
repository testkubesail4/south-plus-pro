#!/usr/bin/env bash
set -euo pipefail

ipa_path="${1:-build/ios/ipa/south_plus_rewrite-ios.ipa}"

app_path=""
for candidate in \
  build/ios/iphoneos/Runner.app \
  build/ios/Release-iphoneos/Runner.app
do
  if [[ -d "${candidate}" ]]; then
    app_path="${candidate}"
    break
  fi
done

if [[ -z "${app_path}" ]]; then
  app_path="$(find build/ios -type d -name Runner.app | head -n 1 || true)"
fi

if [[ -z "${app_path}" ]]; then
  echo "Runner.app was not found. Run flutter build ios --release --no-codesign first." >&2
  exit 1
fi

workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

mkdir -p "${workdir}/Payload"
ditto "${app_path}" "${workdir}/Payload/Runner.app"
mkdir -p "$(dirname "${ipa_path}")"

(
  cd "${workdir}"
  ditto -c -k --sequesterRsrc --keepParent Payload "${OLDPWD}/${ipa_path}"
)
