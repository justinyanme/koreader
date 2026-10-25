#!/usr/bin/env bash
# Symbol gate (Q27, Q35): APP's executable must export every symbol listed in SYMBOLS and every
# @c(ko_ios_*) bridge in the Swift SOURCES. APP must not carry a loose dynamic library (Q1).
set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "usage: $0 APP SYMBOLS SOURCES" >&2
    exit 2
fi
app="$1"
symbols="$2"
sources="$3"

executable="${app}/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "${app}/Info.plist")"
wanted="$({
    sed -e '/^#/d' -e '/^$/d' "${symbols}"
    grep -rhoE '@c\(ko_ios_[A-Za-z0-9_]+\)' "${sources}" | sed -E 's/^@c\((.*)\)$/\1/' || true
} | sort -u)"
exported="$(nm -gUj "${executable}" | sed 's/^_//' | sort -u)"
missing="$(comm -23 <(printf '%s\n' "${wanted}") <(printf '%s\n' "${exported}"))"
libraries="$(find "${app}" -name '*.dylib' -o -name '*.so')"

status=0
if [[ -n "${missing}" ]]; then
    echo "error: ${executable} does not export:"
    printf '  %s\n' ${missing}
    status=1
fi
if [[ -n "${libraries}" ]]; then
    echo "error: loose dynamic libraries in ${app}:"
    printf '  %s\n' ${libraries}
    status=1
fi
if [[ ${status} -eq 0 ]]; then
    echo "symbol gate: $(wc -l <<<"${wanted}" | tr -d ' ') symbols exported, no loose dynamic libraries"
fi
exit ${status}
