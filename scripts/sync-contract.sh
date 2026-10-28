#!/usr/bin/env bash
# Vendor the Attro device contract into the SDK's tests.
#
#   scripts/sync-contract.sh <path to an Attro checkout>
#   scripts/sync-contract.sh --check <path to an Attro checkout>
#
# Copies <attro>/docs/contracts/device/*.json and its checksum list
# (CHECKSUMS.sha256, written by `pnpm contracts:generate` in Attro) to
# Tests/AttroSDKTests/Contract/, replacing what is there, and verifies every
# copied file against the list. --check changes nothing and fails when the
# vendored copy differs from the checkout's.
#
# After a sync: run `swift test` (ContractTests validates every fixture and
# every request the SDK sends against the new schemas), commit the result,
# then in Attro set ios.vendoredChecksumsSha256 in docs/contracts/sdk-pins.json
# to the digest this script prints (tests/unit/sdk-contract-pins.test.ts).
set -euo pipefail

CHECK=0
if [[ "${1:-}" == "--check" ]]; then
  CHECK=1
  shift
fi
ATTRO="${1:?usage: scripts/sync-contract.sh [--check] <path to an Attro checkout>}"
SRC="$ATTRO/docs/contracts/device"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/Tests/AttroSDKTests/Contract"
LIST="CHECKSUMS.sha256"

[[ -f "$SRC/$LIST" && -f "$SRC/contract.json" ]] || {
  echo "no device contract at $SRC (expected contract.json and $LIST)" >&2
  exit 2
}

sha256_check() { # verify the files in the current directory against $LIST
  if command -v sha256sum > /dev/null 2>&1; then sha256sum --quiet -c "$LIST"; else shasum -a 256 --quiet -c "$LIST"; fi
}
sha256_of() {
  if command -v sha256sum > /dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# The source must be consistent before anything is copied.
(cd "$SRC" && sha256_check) || { echo "$SRC does not match its own $LIST: run pnpm contracts:generate there" >&2; exit 1; }
listed() { awk '{ print $2 }' "$1/$LIST" | LC_ALL=C sort; }
present() { (cd "$1" && ls -1 -- *.json | LC_ALL=C sort); }
[[ "$(listed "$SRC")" == "$(present "$SRC")" ]] || { echo "$SRC holds JSON files its $LIST does not list" >&2; exit 1; }

if [[ "$CHECK" == 1 ]]; then
  if diff -r "$SRC" "$DEST" > /dev/null 2>&1; then
    echo "Vendored contract is current ($(sha256_of "$DEST/$LIST"))."
    exit 0
  fi
  echo "Vendored contract differs from $SRC: run scripts/sync-contract.sh $ATTRO" >&2
  diff -r "$SRC" "$DEST" >&2 || true
  exit 1
fi

mkdir -p "$DEST"
find "$DEST" -mindepth 1 -maxdepth 1 -type f -delete
cp "$SRC"/*.json "$SRC/$LIST" "$DEST/"
(cd "$DEST" && sha256_check)
[[ "$(listed "$DEST")" == "$(present "$DEST")" ]]

VERSION="$(sed -n 's/^  "version": "\(.*\)",$/\1/p' "$DEST/contract.json")"
echo "Vendored device contract $VERSION into Tests/AttroSDKTests/Contract/."
echo "Digest of $LIST (Attro docs/contracts/sdk-pins.json ios.vendoredChecksumsSha256):"
sha256_of "$DEST/$LIST"
