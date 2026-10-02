#!/usr/bin/env bash
# Kit Test developer commands, the same locally (Git Bash on Windows, any Linux shell) and in CI.
#   tools/dev.sh <command> [args]
#
#   setup               install or fetch what the project needs (once on a fresh checkout)
#   check               static checks: lint/format, version consistent
#   test [args]         unit tests (CI runs them as the unit-tests check)
#   build               build into build/ (CI uploads it as the test-build artifact)
#   version <x.y.z>     set the version everywhere (VERSION and any Node.js 22 files that carry it)
#
# Logs go to out/. Exit code 0 = pass.
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p out build

# --- Node.js 22 --------------------------------------------------------------------------------
# These functions are the only stack-specific part; everything else comes from the project kit.

stack_setup() {
  # No dependencies: Node 22's built-in test runner. Just confirm Node is there.
  node --version
}

stack_check() {
  # Syntax-check every source file.
  local f fail=0
  for f in src/*.mjs test/*.mjs; do node --check "$f" || fail=1; done
  return $fail
}

stack_test() {
  node --test "$@" test/*.test.mjs
}

# Leave release-ready FILES directly in build/ (an archive, a jar, an exe), not folders: the
# release workflow attaches build/* to the GitHub release.
stack_build() {
  rm -f build/*
  tar -czf "build/kit-test-$(tr -d '[:space:]' < VERSION).tar.gz" src package.json
}

# Write version $1 into the stack's own files (package.json, *.csproj, gradle.properties...).
# Leave empty if VERSION is the only place.
stack_set_version() {
  node -e 'const p = require("./package.json"); p.version = process.argv[1]; require("fs").writeFileSync("package.json", JSON.stringify(p, null, 2) + "\n")' "$1"
}

# Print the version the stack's files carry, or nothing if VERSION is the only place.
stack_get_version() {
  node -p 'require("./package.json").version'
}
# ----------------------------------------------------------------------------------------------

cmd=${1:-help}; shift || true
case "$cmd" in
  setup)
    stack_setup "$@" 2>&1 | tee out/setup.log; exit "${PIPESTATUS[0]}" ;;

  check)
    fail=0
    echo "== version consistent"
    v=$(tr -d '[:space:]' < VERSION)
    s=$(stack_get_version)
    if [ -n "$s" ] && [ "$s" != "$v" ]; then
      echo "VERSION says $v but the stack files say $s: run tools/dev.sh version $v"; fail=1
    else
      echo "ok ($v)"
    fi
    echo "== stack checks"
    stack_check "$@" 2>&1 | tee out/check.log; [ "${PIPESTATUS[0]}" -eq 0 ] || fail=1
    exit $fail ;;

  test)
    stack_test "$@" 2>&1 | tee out/test.log; exit "${PIPESTATUS[0]}" ;;

  build)
    stack_build "$@" 2>&1 | tee out/build.log; exit "${PIPESTATUS[0]}" ;;

  version)
    v=${1:-}
    [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "usage: tools/dev.sh version x.y.z"; exit 2; }
    echo "$v" > VERSION
    stack_set_version "$v"
    echo "version $v" ;;

  help|*)
    sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//' ;;
esac
