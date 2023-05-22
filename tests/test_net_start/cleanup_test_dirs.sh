#!/usr/bin/env bash

TEST_ROOT=`cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P`

cd $TEST_ROOT/../../
NODE_SRC_DIR="$(pwd)"
TEST_WRK_DIR="${NODE_SRC_DIR}/tests/Run_NetWork"
echo "-- Kill all running ton_node"
killall -9 ton_node &>/dev/null
echo "-- Clear prev run arts"
rm -rf $TEST_WRK_DIR

exit 0
