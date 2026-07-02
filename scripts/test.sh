#!/bin/bash
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

raw_log=$(mktemp)
tmp_args=""
cleanup() {
  rm -f "$raw_log"
  if [ -n "$tmp_args" ]; then
    rm -f "$tmp_args"
  fi
}
trap cleanup EXIT

run_and_format() {
  if command -v xcsift >/dev/null 2>&1; then
    "$@" 2>&1 | tee "$raw_log" | xcsift -f toon -w
  else
    "$@" 2>&1 | tee "$raw_log"
  fi
}

# Skipped tests are triage debt in this repo (they have hidden real product bugs), and the xcsift
# TOON summary does not count them — so fail the run whenever raw xcodebuild output reports any.
assert_no_skipped_tests() {
  if grep -Eq "with [1-9][0-9]* tests? skipped" "$raw_log"; then
    echo "error: skipped tests detected; skips are not allowed (fix or remove the test):" >&2
    grep -E "Test [Cc]ase .*skipped|with [1-9][0-9]* tests? skipped" "$raw_log" \
      | sed 's/^[[:space:]]*//' | sort -u | head -20 >&2
    exit 1
  fi
}

if [ "$#" -eq 0 ]; then
  run_and_format xcodebuild \
    -scheme BlockInputKit-Package \
    -destination 'platform=macOS' \
    -derivedDataPath .build/xcode \
    test
  assert_no_skipped_tests
  echo "Tests passed."
  exit 0
fi

tmp_args=$(mktemp)

for test_name in "$@"; do
  printf '%s\0' "-only-testing:$test_name" >> "$tmp_args"
done

run_and_format xargs -0 xcodebuild \
  -scheme BlockInputKit-Package \
  -destination 'platform=macOS' \
  -derivedDataPath .build/xcode \
  test < "$tmp_args"
assert_no_skipped_tests

echo "Tests passed."
