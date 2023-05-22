#!/usr/bin/env bash

RUST_VERSION="1.69.0"

#=============================================
# Install deps
PKGS_Ubuntu="git mc jq vim bc p7zip-full curl build-essential libssl-dev automake libtool clang llvm-dev cmake gawk gperf libz-dev pkg-config zlib1g-dev libzstd-dev libgoogle-perftools-dev"

sudo apt update 
sudo apt install -y $PKGS_Ubuntu

curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- --default-toolchain ${RUST_VERSION} -y
source $HOME/.cargo/env
cargo install cargo-binutils

sudo wget https://github.com/mikefarah/yq/releases/download/v4.13.3/yq_linux_amd64 -O /usr/bin/yq && sudo chmod +x /usr/bin/yq
# curl -sSLf "$(curl -sSLf https://api.github.com/repos/tomwright/dasel/releases/latest | grep browser_download_url | grep linux_amd64 | grep -v .gz | cut -d\" -f 4)" -L -o dasel && chmod +x dasel
# sudo mv ./dasel /usr/local/bin/dasel
#=============================================

exit 0
