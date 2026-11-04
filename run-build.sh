#!/bin/bash
# AirTower build wrapper for zig-png-examples.
# Builds with Zig 0.15 (scripts/zig-path.sh) and writes .build-results.json.
cd "$(dirname "$0")" || exit 1
RESULTS_FILE=".build-results.json"

write_results() {
    printf '{\n  "success": %s,\n  "errors": %d,\n  "warnings": %d\n}\n' "$1" "$2" "$3" > "$RESULTS_FILE"
}

if ! ZIG=$(scripts/zig-path.sh); then
    write_results false 1 0
    exit 1
fi

echo "Building with $ZIG ($("$ZIG" version))..."
OUTPUT=$("$ZIG" build 2>&1)
EXIT_CODE=$?

WARNINGS=$(echo "$OUTPUT" | grep -c "warning:")
ERRORS=0
if [ $EXIT_CODE -ne 0 ]; then
    ERRORS=$(echo "$OUTPUT" | grep -c "error:")
    [ "$ERRORS" -eq 0 ] && ERRORS=1
fi

if [ $EXIT_CODE -eq 0 ]; then
    write_results true 0 "$WARNINGS"
    echo "Build successful."
else
    write_results false "$ERRORS" "$WARNINGS"
    echo "$OUTPUT"
    echo "Build failed with $ERRORS error(s)."
fi
cat "$RESULTS_FILE"
exit $EXIT_CODE
