#!/bin/bash
# TestSprite test suite runner for TaskManagerNative.
# Executes every standalone simulation suite and validates the workflow plans.
set -e
cd "$(dirname "$0")"

echo "=============================================="
echo " TestSprite - TaskManagerNative Test Suite"
echo "=============================================="

PASS=0
FAIL=0

run_suite() {
    echo ""
    echo "--- $1 ---"
    if python3 "$1"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "[FAIL] $1"
    fi
}

run_suite auth_simulation.py
run_suite metrics_verification.py
run_suite error_scenarios.py
run_suite data_integrity.py

echo ""
echo "--- Validating workflow plans ---"
for plan in *.plan.json; do
    if python3 -c "import json,sys; json.load(open('$plan'))" 2>/dev/null; then
        echo "[PASS] $plan is valid JSON"
        PASS=$((PASS + 1))
    else
        echo "[FAIL] $plan is not valid JSON"
        FAIL=$((FAIL + 1))
    fi
done

echo ""
echo "=============================================="
echo " Result: $PASS passed, $FAIL failed"
echo "=============================================="

[ "$FAIL" -eq 0 ]
