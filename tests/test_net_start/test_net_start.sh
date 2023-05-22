#!/usr/bin/env bash

NODES=6

BUILD_NODE=false

TEST_ROOT=`cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P`
cd $TEST_ROOT/../../

#=============================================
# Determine node branch and tools git url
NODE_SRC_DIR="$(pwd)"
CURRENT_BRANCH="$(git branch --show-current)"
echo "Current branch: $CURRENT_BRANCH"
Node_Name="${NODE_SRC_DIR##*/}"         # determine node visibility: private/public ever-node-private or ever-node
Suffix="$(echo $Node_Name|awk -F'-' '{print $3}')" # 'private' or '' or smth else

cd ..
TOP_DIR="$(pwd)"
export TEST_WRK_DIR="${NODE_SRC_DIR}/tests/Run_NetWork"

if [[ -n "$Suffix" ]];then
    TOOLS_SRC_DIR="${TOP_DIR}/ever-node-tools-${Suffix}"
    TOOLS_GIT_URL="git@github.com:tonlabs/ever-node-tools-${Suffix}.git"
else
    TOOLS_SRC_DIR="${TOP_DIR}/ever-node-tools"
    TOOLS_GIT_URL="https://github.com/tonlabs/ever-node-tools.git"
fi

#=============================================
# Set binaries paths
RNODE_BIN="$NODE_SRC_DIR/target/release/ton_node"
RCONS_BIN="$TOOLS_SRC_DIR/target/release/console"
KEYGEN_BIN="$TOOLS_SRC_DIR/target/release/keygen"
ZS_BIN="$TOOLS_SRC_DIR/target/release/zerostate"
GDHT_BIN="$TOOLS_SRC_DIR/target/release/gendht"
ZS_DIR="$TEST_WRK_DIR/zerostate"

#=============================================
# To build node and tools from private repo,
# you need read acckey
# and proper config file in ~/.ssh
eval $(ssh-agent -k; ssh-agent -s)

#=============================================
# Clear prev run if any
echo "--- Preparations... ---"
echo "-- Kill all running ton_node"
pkill -9 ton_node &>/dev/null
echo "-- Clear prev run arts"
rm -rf "$TEST_WRK_DIR"
mkdir -p "$TEST_WRK_DIR"

#=============================================
# Build node if enabled
if $BUILD_NODE || [[ ! -x "$RNODE_BIN" ]];then
    echo
    echo "--- Build new node"
    cd $NODE_SRC_DIR
    git pull --recurse-submodules
    cargo update
    if ! cargo build --release;then
        echo "###-ERROR: Node build FAILED!"
        exit 1
    else 
        echo "--- Build Node done"
    fi

    echo
    echo "--- Build tools"
fi

#=============================================
# Build tools if not builded
if [[ ! -d "$TOOLS_SRC_DIR" ]] || [[ ! -x "$RCONS_BIN" ]];then
    git clone --recursive "$TOOLS_GIT_URL"
    cd "$TOOLS_SRC_DIR"
    git pull --recurse-submodules
    git checkout "$CURRENT_BRANCH" || echo "Use default branch"
    cargo update
    if ! cargo build --release;then
        echo
        echo "###-ERROR: Tools build FAILED!"
        echo "           Will try to build from master branch..."
        git checkout master
        git pull --recurse-submodules
        cargo update
        cargo build --release
    else 
        echo "--- Build Tools done"
    fi
fi

#=============================================
# Check binaries present
if [[ ! -x "$RNODE_BIN" ]] || [[ ! -x "$RCONS_BIN" ]] || [[ ! -x "$KEYGEN_BIN" ]];then
    echo
    echo "###-ERROR: Not all binaries were built! Can't continue."
    exit 1
fi

CurrUnixTime=$(date +"%s")
# NOWIP=$(curl ifconfig.me)
NOWIP="127.0.0.1"
echo "  IP = $NOWIP"

declare -A VALIDATOR_PUB_KEY_HEX=();

#=============================================
#  Fake config just to start nodes for generate keys
cp -f "$TEST_ROOT/ton-global.config.json" "$TEST_WRK_DIR/ton-global.config.json"

#=============================================
# Generate keys and etc for 
# 0 is full node
for (( NodeNum=0; NodeNum <= NODES; NodeNum++ ));do
    echo "Validator's Noded #$NodeNum config generating..."
    cd "$TEST_WRK_DIR"
    killall -9 ton_node &>/dev/null
    mkdir -p "$TEST_WRK_DIR/configs_$NodeNum"
    mkdir -p "$TEST_WRK_DIR/node_db_$NodeNum"
    mkdir -p "$TEST_WRK_DIR/logs_$NodeNum"

    # path to log file
    sed "s|LOG_PATH|$TEST_WRK_DIR/logs_$NodeNum|g" "$TEST_ROOT/log_cfg.yml" > $TEST_WRK_DIR/configs_$NodeNum/log_cfg.yml

    #===========================================
    # Set rnode console keys
    "$KEYGEN_BIN" > "$TEST_WRK_DIR/configs_$NodeNum/genkey"
    jq -c .public "$TEST_WRK_DIR/configs_$NodeNum/genkey" > "$TEST_WRK_DIR/configs_$NodeNum/console_public.json"

    #=============================================
    # Configure default config
    if [[ $NodeNum -ne 0 ]]; then
        cp "$TEST_ROOT/default_config.json" "$TEST_WRK_DIR/configs_$NodeNum/default_config.json"
    else 
        cp "$TEST_ROOT/default_config_fullnode.json" "$TEST_WRK_DIR/configs_$NodeNum/default_config.json"
    fi

    UDP_PORT=$(( 30000 + NodeNum ))
    CTRL_PORT=$(( 49200 + NodeNum ))
    
    jq      ".log_config_name = \"$TEST_WRK_DIR/configs_$NodeNum/log_cfg.yml\" | \
            .ton_global_config_name = \"$TEST_WRK_DIR/ton-global.config.json\" | \
            .internal_db_path = \"$TEST_WRK_DIR/node_db_$NodeNum\" | \
            .ip_address = \"${NOWIP}:${UDP_PORT}\" | \
            .control_server_port = ${CTRL_PORT}" \
        "$TEST_WRK_DIR/configs_$NodeNum/default_config.json" \
      > "$TEST_WRK_DIR/configs_$NodeNum/default_config.tmp.json"
    mv -f "$TEST_WRK_DIR/configs_$NodeNum/default_config.tmp.json" "$TEST_WRK_DIR/configs_$NodeNum/default_config.json"

    #===========================================
    # Generate rnode config.json
    # echo "---cmd: $RNODE_BIN --configs \"$TEST_WRK_DIR/configs_$NodeNum\" --ckey \"$(cat "$TEST_WRK_DIR/configs_$NodeNum/console_public.json")\" > \"$TEST_WRK_DIR/logs_$NodeNum/gen_output\""
    $RNODE_BIN --configs "$TEST_WRK_DIR/configs_$NodeNum" --ckey "$(cat "$TEST_WRK_DIR/configs_$NodeNum/console_public.json")" > "$TEST_WRK_DIR/logs_$NodeNum/gen_output" &
    # bash "$TEST_ROOT/node_run.sh" "$RNODE_BIN" "$TEST_WRK_DIR" "$NodeNum"

    echo "  waiting for 10 secs"
    sleep 10
    if [[ ! -f "$TEST_WRK_DIR/configs_$NodeNum/console_config.json" ]];then
        echo "ERROR: console_config.json does not exist"
        exit 1
    fi

    # cp -f "$TEST_WRK_DIR/configs_$NodeNum/console_config.json" "$TEST_WRK_DIR/configs_$NodeNum/console.json"
    jq ".client_key = $(jq .private "$TEST_WRK_DIR/configs_$NodeNum/genkey")" "$TEST_WRK_DIR/configs_$NodeNum/console_config.json" > "$TEST_WRK_DIR/configs_$NodeNum/console.tmp.json"
    jq ".config = $(cat "$TEST_WRK_DIR/configs_$NodeNum/console.tmp.json")" "$TEST_ROOT/console-template.json" > "$TEST_WRK_DIR/configs_$NodeNum/console.json"

    #===========================================
    #     VALIDATOR_PUB_KEY_HEX
    # 0 is full node
    if [[ $NodeNum -ne 0 ]];then
        CONSOLE_OUTPUT=$($RCONS_BIN -C "$TEST_WRK_DIR/configs_$NodeNum/console.json" -jc newkey | awk '{print $5}')
        $RCONS_BIN -C "$TEST_WRK_DIR/configs_$NodeNum/console.json" -c "addpermkey ${CONSOLE_OUTPUT} ${CurrUnixTime} 1610000000" > "$TEST_WRK_DIR/logs_$NodeNum/gen_console_output"
        CONSOLE_OUTPUT=$($RCONS_BIN -C "$TEST_WRK_DIR/configs_$NodeNum/console.json" -c "exportpub ${CONSOLE_OUTPUT}")
        #echo "=== CONSOLE_OUTPUT: $CONSOLE_OUTPUT"
        VALIDATOR_PUB_KEY_HEX[$NodeNum]=$(echo "${CONSOLE_OUTPUT}" | grep 'imported key:' | awk '{print $3}')
        # VALIDATOR_PUB_KEY_BASE64[$N]=$(echo "${CONSOLE_OUTPUT}" | grep 'imported key:' | awk '{print $4}')
        # echo "INFO: VALIDATOR_PUB_KEY_HEX[$NodeNum] = ${VALIDATOR_PUB_KEY_HEX[$]}"
        # echo "INFO: VALIDATOR_PUB_KEY_BASE64[$N] = ${VALIDATOR_PUB_KEY_BASE64[$N]}"
    fi

    #cp $NODE_TARGET/config.json $TEST_ROOT/tmp/config$N.json
    killall -9 ton_node &>/dev/null
    jq '.low_memory_mode = true' "$TEST_WRK_DIR/configs_$NodeNum/config.json" > "$TEST_WRK_DIR/configs_$NodeNum/config.json.tmp" && \
    mv -f "$TEST_WRK_DIR/configs_$NodeNum/config.json.tmp" "$TEST_WRK_DIR/configs_$NodeNum/config.json"
done

#===========================================
# Zerostate compose
echo
echo "--- Zerostate generating..."
mkdir -p "$ZS_DIR"
cp -f  "$TEST_ROOT/zero_state_blanc.json" "$ZS_DIR/zero_state_tmp.json"

WEIGHT=10
TOTAL_WEIGHT=$(( $NODES * 2 ))

cat "$ZS_DIR/zero_state_tmp.json" | jq \
".gen_utime = $CurrUnixTime | \
 .master.config.p12[0].enabled_since = $CurrUnixTime | \
 .master.config.p34.utime_since = $CurrUnixTime | \
 .master.config.p34.total = $NODES | \
 .master.config.p34.total_weight = $TOTAL_WEIGHT" > "$ZS_DIR/zero_state_tmp-1.json"
mv -f "$ZS_DIR/zero_state_tmp-1.json" "$ZS_DIR/zero_state_tmp.json"

echo
echo "--- Validators contract processing:"
ValNodesList="[]"
i=0
for (( NodeNum=1; NodeNum <= NODES; NodeNum++ ));do
    echo "  Validator #$NodeNum contract processing..."
    printf -v CurrNodeP34 "{ \"public_key\": \"%s\", \"weight\": \"%d\"}" "${VALIDATOR_PUB_KEY_HEX[$NodeNum]}" "$WEIGHT"
    ValNodesList=$(echo "$ValNodesList" | jq ".[$i] = $CurrNodeP34")
    i=$((i + 1))
done
cat "$ZS_DIR/zero_state_tmp.json" | jq \
".master.config.p34.list = $ValNodesList" > "$ZS_DIR/zero_state.json"

cd "$ZS_DIR"
P12_min_split=$(jq -r .master.config.p12[0].min_split "$ZS_DIR/zero_state.json")
echo "--- finish zerostate generating..."
$ZS_BIN --input "$ZS_DIR/zero_state.json" > "${ZS_DIR}/zerostate_hash.json"
rm -f "${ZS_DIR}"/zero_state*

#===========================================
# generate global config
# Add nodes to global config
echo
echo "--- Global config generating..."
NetGlobalConfig="$(cat "$TEST_WRK_DIR/ton-global.config.json")"
i=0
for (( NodeNum=1; NodeNum <= NODES; NodeNum++ ));do
    NODE_PRIVATE_KEY_BASE64="$(jq -r .adnl_node.keys[0].data.pvt_key "$TEST_WRK_DIR/configs_$NodeNum/config.json")"
    IP_PORT="$(jq -r .adnl_node.ip_address "$TEST_WRK_DIR/configs_$NodeNum/config.json")"
    NODE_NETWORK_CONFIG_RECORD=$($GDHT_BIN "${IP_PORT}" "${NODE_PRIVATE_KEY_BASE64}" | jq -c .)
    NetGlobalConfig="$( echo "${NetGlobalConfig}" | jq ".dht.static_nodes.nodes[$i] |= . + ${NODE_NETWORK_CONFIG_RECORD}")"
    i=$((i + 1))
done
# Change fake zeroblock hashes to real
root_hash="$(jq -r .zero_state.root_hash "${ZS_DIR}/zerostate_hash.json")"
file_hash="$(jq -r .zero_state.file_hash "${ZS_DIR}/zerostate_hash.json")"
NetGlobalConfig="$(echo "${NetGlobalConfig}" | jq ".validator.zero_state.root_hash = \"${root_hash}\" | .validator.zero_state.file_hash = \"${file_hash}\"")"

# W/A: -9223372036854775808 is too big for jq and jq cuts it
NetGlobalConfig="$( echo "${NetGlobalConfig}" | sed 's/9223372036854776000/9223372036854775808/')"
echo "$NetGlobalConfig" > "$TEST_WRK_DIR/ton-global.config.json"

#===========================================
# Start network
echo
echo "---- Starting nodes..."

for (( NodeNum=0; NodeNum <= NODES; NodeNum++ ));do
    echo "--  Starting node #$NodeNum..."
    ($RNODE_BIN --configs $TEST_WRK_DIR/configs_$NodeNum --zerostate $ZS_DIR > "$TEST_WRK_DIR/logs_$NodeNum/node.log" 2>&1 & wait 2>/dev/null) &
    # ($RNODE_BIN --configs $TEST_WRK_DIR/configs_$NodeNum --zerostate $ZS_DIR > "$TEST_WRK_DIR/logs_$NodeNum/node.log" 2>&1 & process_id=$! & wait $process_id 2>/dev/null) &
    # ($NODE_BIN --configs configs_$N -z . > /shared/output_$N.log 2>&1 & wait 2>/dev/null) &
done

echo
date  +'%F %T %Z'
echo "Waiting 10 mins for 200th master block"
sleep 600
TestPass=true
#===========================================
#
function find_block {
    for (( NodeNum=0; NodeNum <= NODES; NodeNum++ ));do
        if cat "$TEST_WRK_DIR/logs_$NodeNum/output.log" | egrep -q "Applied(.*)$1";then
            echo "Applied block ($1) - FOUND on node #$NodeNum!"
        else
            echo "ERROR: Can't find applied block ($1) on node #$NodeNum!"
            TestPass=false
        fi
    done
}
#===========================================
# Check MC work
echo
echo "--- Check masterchain on nodes"
find_block "-1:8000000000000000, 200"

echo
date  +'%F %T %Z'
echo "Waiting 10 mins more for all shard's 200th blocks"
sleep 600

#===========================================
# Check shards according to P12 min_split 
echo
echo "--- Check workchain shards on node"
ShBase=0x8000000000000000
Shards_QTY=$(( 2 ** P12_min_split ))
echo "--- ZS min Shards QTY: $Shards_QTY"
mask=$(( ~ ( (2 ** (P12_min_split + 1) - 2) << (63 - P12_min_split) ) ))
shard0=$(( ShBase >> ( P12_min_split ) & mask))
for (( ShNum=0; ShNum < Shards_QTY; ShNum++ ));do
    # printf "shard #: %x\n" $ShNum
    CurrShard=$(( ( ShNum << (64 - P12_min_split) ) + shard0 ))
    # printf "CurrShard : 0:%016x\n" $CurrShard
    printf -v SearchShard  "0:%016x" $CurrShard
    find_block "${SearchShard}, 200"
done

# killall -9 ton_node

echo
if $TestPass;then
    echo "###-INFO: $(date  +'%F %T %Z') --- Test Passed successfully!"
    echo "###-INFO: The network still working. To kill all nodes and clear test files, run 'cleanup_test_dirs.sh' script"
    exit 0
else
    echo "###-ERROR: $(date  +'%F %T %Z') --- TEST FAILED!!"
    killall -9 ton_node
    echo "All nodes killed.."
    exit 1
fi
