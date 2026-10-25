#!/usr/bin/env bash
# Xcode post-build phase: embed the Lua payload, then the symbol gate.
set -euo pipefail

app="${TARGET_BUILD_DIR}/${WRAPPER_NAME}"
# /usr/bin/rsync: a Homebrew rsync on PATH breaks Xcode's own copies (doc/ios/delivery.md).
/usr/bin/rsync -a --delete "${KO_INSTALL_DIR}/payload/" "${app}/koreader/"
exec "${SRCROOT}/scripts/check-symbols.sh" "${app}" "${SRCROOT}/ffi-symbols.txt" "${SRCROOT}/JustReader/Sources"
