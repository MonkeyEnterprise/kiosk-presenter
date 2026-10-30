#!/bin/bash

# =============================================================================
# Test Runner
# -----------------------------------------------------------------------------
# Builds a Debian 12 test image and runs every test/*_test.sh in its own
# container, with the repository mounted read-only at /repo. Requires Docker.
#
# Usage:
#   ./test/run.sh                       Run all tests
#   ./test/run.sh migrate_test.sh       Run one test
#
# Author: Lorenzo Pouw 2025
# Project: https://github.com/MonkeyEnterprise/kiosk-presenter
# =============================================================================

TEST_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_DIR=$(dirname "$TEST_DIR")
IMAGE="kiosk-presenter-test"

docker build -q -t "$IMAGE" "$TEST_DIR" > /dev/null || exit 1

if [ "$#" -gt 0 ]; then
    tests=("$@")
else
    tests=($(cd "$TEST_DIR" && ls *_test.sh))
fi

failed=0
for test in "${tests[@]}"; do
    echo "######## $test"
    docker run --rm -v "$REPO_DIR:/repo:ro" "$IMAGE" bash "/repo/test/$(basename "$test")" || failed=1
    echo
done

exit $failed
