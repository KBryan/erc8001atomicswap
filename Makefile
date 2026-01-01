# ERC-8001 SDK Makefile
# ══════════════════════════════════════════════════════════════════════════════

-include .env

.PHONY: all build test clean deploy verify

# ══════════════════════════════════════════════════════════════════════════════
# BUILD & TEST
# ══════════════════════════════════════════════════════════════════════════════

all: build

build:
	forge build

test:
	forge test -vvv

test-gas:
	forge test --gas-report

clean:
	forge clean

# ══════════════════════════════════════════════════════════════════════════════
# DEPLOYMENT - BASE SEPOLIA
# ══════════════════════════════════════════════════════════════════════════════

# Deploy AtomicSwap only
deploy-swap:
	forge script script/DeployAtomicSwap.s.sol:DeployAtomicSwap \
		--rpc-url base_sepolia \
		--broadcast \
		--verify \
		-vvvv

# Deploy AtomicSwap + mock tokens for testing
deploy-swap-mocks:
	forge script script/DeployAtomicSwap.s.sol:DeployAtomicSwapWithMocks \
		--rpc-url base_sepolia \
		--broadcast \
		-vvvv

# Dry run (simulate without broadcasting)
deploy-swap-dry:
	forge script script/DeployAtomicSwap.s.sol:DeployAtomicSwap \
		--rpc-url base_sepolia \
		-vvvv

# ══════════════════════════════════════════════════════════════════════════════
# VERIFICATION
# ══════════════════════════════════════════════════════════════════════════════

# Verify a deployed contract
# Usage: make verify-swap SWAP_ADDRESS=0x...
verify-swap:
	forge verify-contract $(SWAP_ADDRESS) \
		src/contracts/examples/AtomicSwap.sol:AtomicSwap \
		--chain base-sepolia \
		--etherscan-api-key $(BASESCAN_API_KEY)

# ══════════════════════════════════════════════════════════════════════════════
# UTILITIES
# ══════════════════════════════════════════════════════════════════════════════

# Install dependencies
install:
	forge install OpenZeppelin/openzeppelin-contracts --no-commit
	forge install foundry-rs/forge-std --no-commit

# Format code
fmt:
	forge fmt

# Generate gas snapshots
snapshot:
	forge snapshot

# ══════════════════════════════════════════════════════════════════════════════
# HELP
# ══════════════════════════════════════════════════════════════════════════════

help:
	@echo "ERC-8001 SDK - Available Commands"
	@echo ""
	@echo "Build & Test:"
	@echo "  make build          - Compile contracts"
	@echo "  make test           - Run tests"
	@echo "  make test-gas       - Run tests with gas report"
	@echo "  make clean          - Clean build artifacts"
	@echo ""
	@echo "Deploy (Base Sepolia):"
	@echo "  make deploy-swap       - Deploy AtomicSwap (with verification)"
	@echo "  make deploy-swap-mocks - Deploy AtomicSwap + mock tokens + fund accounts"
	@echo "  make deploy-swap-dry   - Simulate deployment (no broadcast)"
	@echo ""
	@echo "Verification:"
	@echo "  make verify-swap SWAP_ADDRESS=0x... - Verify deployed contract"
	@echo ""
	@echo "Setup:"
	@echo "  make install        - Install Foundry dependencies"
	@echo "  make fmt            - Format Solidity code"
	@echo ""
	@echo "Environment (.env):"
	@echo "  PRIVATE_KEY       - Deployer private key"
	@echo "  BASESCAN_API_KEY  - For contract verification"
	@echo "  AGENT_ONE         - Test account 1 (receives USDC)"
	@echo "  PLAYER_ONE        - Test account 2 (receives WETH)"
