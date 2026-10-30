#!/bin/bash

# =============================================================================
# Test Helpers
# -----------------------------------------------------------------------------
# Sourced by the test/*_test.sh files.
#
#   check '<condition>' "<description>"   evaluate a condition, count the result
#   finish                                print the result, exit 1 on a failure
#
# Author: Lorenzo Pouw 2025
# Project: https://github.com/MonkeyEnterprise/kiosk-presenter
# =============================================================================

PASS=0
FAIL=0

check() {
    if eval "$1"; then
        echo "  PASS: $2"
        PASS=$((PASS+1))
    else
        echo "  FAIL: $2"
        FAIL=$((FAIL+1))
    fi
}

finish() {
    echo
    echo "== Result: $PASS passed, $FAIL failed"
    [ "$FAIL" -eq 0 ]
}
