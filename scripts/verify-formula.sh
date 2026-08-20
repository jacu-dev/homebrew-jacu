#!/usr/bin/env bash
# Refuse a tap formula that does not install a signed jacu-harness release.
set -euo pipefail
cd "$(dirname "$0")/.."

formula="Formula/jacu.rb"
if [ ! -f "$formula" ]; then
  echo "verify-formula: missing $formula" >&2
  exit 1
fi

version="$(sed -n 's/^  version "\([^"]*\)"/\1/p' "$formula" | head -n 1)"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "verify-formula: invalid version $version" >&2
  exit 1
fi
tag="v${version}"

if grep -E 'url "' "$formula" | grep -v "https://github.com/jacu-dev/jacu-harness/releases/download/${tag}/"; then
  echo "verify-formula: formula url is not the signed $tag release" >&2
  exit 1
fi

mapfile -t hashes < <(sed -n 's/.*sha256 "\([a-f0-9]\{64\}\)".*/\1/p' "$formula")
if [ "${#hashes[@]}" -lt 4 ]; then
  echo "verify-formula: need sha256 for every platform tarball" >&2
  exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
base="https://github.com/jacu-dev/jacu-harness/releases/download/${tag}"
curl -fsSL -o "$work/checksums.txt" "$base/checksums.txt"
curl -fsSL -o "$work/checksums.txt.sigstore.json" "$base/checksums.txt.sigstore.json"

if ! command -v cosign >/dev/null; then
  echo "verify-formula: required command missing: cosign" >&2
  exit 1
fi
cosign verify-blob \
  --bundle "$work/checksums.txt.sigstore.json" \
  --certificate-identity-regexp '^https://github.com/jacu-dev/jacu-harness/.github/workflows/release.yml@refs/tags/v.*$' \
  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com' \
  "$work/checksums.txt" >/dev/null

for hash in "${hashes[@]}"; do
  if ! grep -q "$hash" "$work/checksums.txt"; then
    echo "verify-formula: sha256 $hash is not in the signed checksums" >&2
    exit 1
  fi
done

echo "verify-formula: OK ($tag)"
