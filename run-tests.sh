#!/bin/bash
# AirTower test wrapper for zig-png-examples.
# Runs `zig build test` with Zig 0.15 (scripts/zig-path.sh) and writes .test-results.json.
cd "$(dirname "$0")" || exit 1
RESULTS_FILE=".test-results.json"

write_results() {
    printf '{\n  "passed": %d,\n  "failed": %d,\n  "total": %d\n}\n' "$1" "$2" "$(($1 + $2))" > "$RESULTS_FILE"
}

if ! ZIG=$(scripts/zig-path.sh); then
    write_results 0 1
    exit 1
fi

echo "Testing with $ZIG ($("$ZIG" version))..."
OUTPUT=$("$ZIG" build test --summary all 2>&1)
EXIT_CODE=$?

# Read the totals from the one "Build Summary:" line, e.g.
# "Build Summary: 3/5 steps succeeded; 1 failed; 5/6 tests passed; 1 skipped; 1 failed".
SUMMARY=$(echo "$OUTPUT" | grep -m1 '^Build Summary:')
COUNTS=$(echo "$SUMMARY" | grep -oE '[0-9]+/[0-9]+ tests passed')
PASSED=0
FAILED=0
if [ -n "$COUNTS" ]; then
    PASSED=${COUNTS%%/*}
    TOTAL=$(echo "$COUNTS" | grep -oE '/[0-9]+' | tr -d /)
    SKIPPED=$(echo "${SUMMARY#*tests passed}" | grep -oE '[0-9]+ skipped' | grep -oE '[0-9]+')
    FAILED=$((TOTAL - PASSED - ${SKIPPED:-0}))
fi
if [ $EXIT_CODE -ne 0 ] && [ "$FAILED" -eq 0 ]; then
    FAILED=1  # build error or crash: no counts, but not green
fi

write_results "$PASSED" "$FAILED"
if [ $EXIT_CODE -eq 0 ]; then
    echo "All $PASSED tests passed."
else
    echo "$OUTPUT"
    echo "$PASSED passed, $FAILED failed."
fi
cat "$RESULTS_FILE"
exit $EXIT_CODE
