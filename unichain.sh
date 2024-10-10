#!/bin/bash

# Color and style definitions
BOLD=$(tput bold)
NORMAL=$(tput sgr0)
PINK='\033[1;35m'

# Function to display messages
show() {
    case $2 in
        "error")
            echo -e "${PINK}${BOLD}❌ $1${NORMAL}"
            ;;
        "progress")
            echo -e "${PINK}${BOLD}⏳ $1${NORMAL}"
            ;;
        *)
            echo -e "${PINK}${BOLD}✅ $1${NORMAL}"
            ;;
    esac
}

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit

# Loop for repeated deployment
while true; do
    # Getting user input
    read -p "Enter your Private Key: " PRIVATE_KEY
    read -p "Enter the token name (e.g., Golden BEE): " TOKEN_NAME
    read -p "Enter the token symbol (e.g., GDB): " TOKEN_SYMBOL

    # Creating a directory for deployment files
    mkdir -p "$SCRIPT_DIR/token_deployment"
    cat <<EOL > "$SCRIPT_DIR/token_deployment/.env"
PRIVATE_KEY="$PRIVATE_KEY"
TOKEN_NAME="$TOKEN_NAME"
TOKEN_SYMBOL="$TOKEN_SYMBOL"
EOL

    # Contract settings
    CONTRACT_NAME="GoldenBEE"

    # Initializing Git repository (if not exists)
    if [ ! -d ".git" ]; then
        show "Initializing Git repository..." "progress"
        git init
    fi

    # Installing Foundry (if not installed)
    if ! command -v forge &> /dev/null; then
        show "Foundry is not installed. Installing now..." "progress"
        source <(wget -O - https://raw.githubusercontent.com/AgataGolik/installation/main/foundry.sh)
    fi

    # Installing OpenZeppelin Contracts (if not installed)
    if [ ! -d "$SCRIPT_DIR/lib/openzeppelin-contracts" ]; then
        show "Installing OpenZeppelin Contracts..." "progress"
        git clone https://github.com/OpenZeppelin/openzeppelin-contracts.git "$SCRIPT_DIR/lib/openzeppelin-contracts"
    else
        show "OpenZeppelin Contracts already installed."
    fi

    # Creating foundry.toml (if not exists)
    if [ ! -f "$SCRIPT_DIR/foundry.toml" ]; then
        show "Creating foundry.toml and adding Unichain RPC..." "progress"
        cat <<EOL > "$SCRIPT_DIR/foundry.toml"
[profile.default]
src = "src"
out = "out"
libs = ["lib"]

[rpc_endpoints]
unichain = "https://sepolia.unichain.org"
EOL
    else
        show "foundry.toml already exists."
    fi

    # Creating the ERC-20 contract
    show "Creating ERC-20 token contract using OpenZeppelin..." "progress"
    mkdir -p "$SCRIPT_DIR/src"
    cat <<EOL > "$SCRIPT_DIR/src/$CONTRACT_NAME.sol"
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract $CONTRACT_NAME is ERC20 {
    constructor() ERC20("$TOKEN_NAME", "$TOKEN_SYMBOL") {
        _mint(msg.sender, 100000 * (10 ** decimals()));
    }
}
EOL

    # Compiling the contract
    show "Compiling the contract..." "progress"
    forge build

    if [[ $? -ne 0 ]]; then
        show "Contract compilation failed." "error"
        exit 1
    fi

    # Deploying the contract
    show "Deploying the contract to Unichain..." "progress"
    DEPLOY_OUTPUT=$(forge create "$SCRIPT_DIR/src/$CONTRACT_NAME.sol:$CONTRACT_NAME" \
        --rpc-url unichain \
        --private-key "$PRIVATE_KEY")

    if [[ $? -ne 0 ]]; then
        show "Deployment failed." "error"
        exit 1
    fi

    # Extract and display the contract address
    CONTRACT_ADDRESS=$(echo "$DEPLOY_OUTPUT" | grep -oP 'Deployed to: \K(0x[a-fA-F0-9]{40})')
    show "Token deployed successfully at address: https://sepolia.uniscan.xyz/address/$CONTRACT_ADDRESS"

    # Asking if the user wants to deploy another contract
    read -p "Do you want to deploy another contract? (y/n): " REDEPLOY
    if [[ "$REDEPLOY" != "y" ]]; then
        show "Deployment process finished." "progress"
        break
    fi
done
