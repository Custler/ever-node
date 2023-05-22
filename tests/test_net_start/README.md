# Network emulation test

## NB! You have to have enough memory and num of CPU threads
If memory will be less than needed, nodes will start and then crash and the network will not run

### 1. Install dependencies

```bash
./install_deps.sh
```
it will install rust and all deps

### 2. Start test script

```bash
./test_net_start.sh
```

The script will build node and tools (if it's not built before) according to suffix (-prvate, -venom, etc),
configure the network and run all nodes.
10 min after the network started, It will check num of  blocks in master chain
after next 10 mins, it will check all shards on all nodes according to settings in P12 min_split parameter

### 3. Stop the network and clear all files produced by test

```bash
cleanup_test_dirs.sh
```

It will kill all nodes and delete all files
