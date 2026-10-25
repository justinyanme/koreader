#!/usr/bin/env bash
# Xcode pre-build phase: koreader-base for this SDK, the Lua payload and link.args (make/ios.mk).
set -euo pipefail

# Not Xcode's PATH: its toolchain clang has no default sysroot, which breaks the host compiler.
# The KOReader build needs the system tools, Homebrew and its GNU tools.
path="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
brew_prefix="$(PATH="${path}" brew --prefix)"
for tool in findutils/libexec/gnubin gnu-getopt/bin make/libexec/gnubin util-linux/bin; do
    path="${brew_prefix}/opt/${tool}:${path}"
done

# Start make from a clean environment: Xcode exports build settings such as INSTALL_DIR that the
# KOReader makefiles would pick up, and under `kodev build ios` the outer make's jobserver too.
exec env -i HOME="${HOME}" USER="${USER}" TMPDIR="${TMPDIR}" PATH="${path}" DEVELOPER_DIR="${DEVELOPER_DIR}" \
    make -C "${KO_ROOT}" TARGET=ios KODEBUG= IOS_PLATFORM="${PLATFORM_NAME}" \
    IOS_DEPLOYMENT_TARGET="${IPHONEOS_DEPLOYMENT_TARGET}" IOS_GATE_DROP="${IOS_GATE_DROP:-}" xcode-prepare
