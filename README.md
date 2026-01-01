# ERC-8001 SDK

Agent Coordination Framework - Solidity contracts and TypeScript SDK for multi-party agent coordination on Ethereum.

## Overview

ERC-8001 defines a minimal, single-chain primitive for multi-party agent coordination. This SDK provides:

- **Solidity Contracts**: Base implementations of ERC-8001 and BoundedAgentExecutor
- **TypeScript SDK**: EIP-712 signing utilities for intents and attestations
- **Examples**: AtomicSwap - the "Hello World" of ERC-8001
- **Deployment Scripts**: Ready for Base Sepolia

## The Problem ERC-8001 Solves

Multiple parties need to agree before something happens, and you need cryptographic proof of each party's consent.

**Without ERC-8001**: Trust a centralized coordinator, build custom signature verification, or use complex multi-sig patterns.

**With ERC-8001**: Standard primitive for "propose → accept → execute" with EIP-712 signatures.

## Quick Start: AtomicSwap Example

The simplest demonstration of ERC-8001 - two parties swap tokens trustlessly:

```
Alice has 100 USDC, wants 0.1 WETH
Bob has 0.1 WETH, wants 100 USDC

1. Alice proposes swap (signs intent)
2. Bob accepts (signs acceptance)  
3. Anyone calls execute → tokens swap atomically
```

No intermediary. No trust. If either party backs out, nothing happens.

## Deployed Contracts (Base Sepolia)

| Contract | Address |
|----------|---------|
| AtomicSwap | `0xD25FaF692736b74A674c8052F904b5C77f9cb2Ed` |
| Mock USDC | `0x17abd6d0355cB2B933C014133B14245412ca00B6` |
| Mock WETH | `0xddFaC73904FE867B5526510E695826f4968A2357` |

[View on BaseScan](https://sepolia.basescan.org/address/0xD25FaF692736b74A674c8052F904b5C77f9cb2Ed)

## Installation

```bash
# Clone the repo
git clone https://github.com/anthropic/erc8001-sdk
cd erc8001-sdk

# Install Foundry dependencies
make install

# Build
make build

# Test
make test
```

## Complete Swap Flow (Forge Commands)

This is the complete tested flow for executing an atomic swap using Foundry scripts.

### Prerequisites

Set up environment variables:

```bash
# Private keys
export AGENT_ONE_PK=0x...    # Alice's private key
export PLAYER_ONE_PK=0x...   # Bob's private key

# Derive addresses (or set manually)
export AGENT_ONE=$(cast wallet address $AGENT_ONE_PK)
export PLAYER_ONE=$(cast wallet address $PLAYER_ONE_PK)
```

### Step 0: Approve Tokens (One-time)

```bash
# Alice approves USDC
PRIVATE_KEY=$AGENT_ONE_PK \
forge script script/SwapScripts.s.sol:ApproveUSDC \
  --rpc-url https://sepolia.base.org --broadcast

# Bob approves WETH
PRIVATE_KEY=$PLAYER_ONE_PK \
forge script script/SwapScripts.s.sol:ApproveWETH \
  --rpc-url https://sepolia.base.org --broadcast
```

### Step 1: Propose Swap (Alice)

```bash
PRIVATE_KEY=$AGENT_ONE_PK \
COUNTERPARTY=$PLAYER_ONE \
forge script script/SwapScripts.s.sol:ProposeSwap \
  --rpc-url https://sepolia.base.org --broadcast -vvvv
```

**Output:**
```
Proposer: 0x865aa4dec65FF12d29C5b24b16FA95994ae1e46a
Counterparty: 0xD984d30B29793eFef8acF09a42C11D84445f7B43
Intent Hash: 0xa59b9660...  # Save this!
```

### Step 2: Accept Swap (Bob)

```bash
PRIVATE_KEY=$PLAYER_ONE_PK \
INTENT_HASH=0xa59b96601aff4b29e7a35ffbe135f660f5ae34a1d74772f22f50648d43a8dffe \
forge script script/SwapScripts.s.sol:AcceptSwap \
  --rpc-url https://sepolia.base.org --broadcast -vvvv
```

**Output:**
```
Acceptor: 0xD984d30B29793eFef8acF09a42C11D84445f7B43
Intent: 0xa59b96601aff4b29e7a35ffbe135f660f5ae34a1d74772f22f50648d43a8dffe
Status: 1
Accepted! New status: 2
```

### Step 3: Execute Swap (Anyone)

```bash
PRIVATE_KEY=$AGENT_ONE_PK \
INTENT_HASH=0xa59b96601aff4b29e7a35ffbe135f660f5ae34a1d74772f22f50648d43a8dffe \
PROPOSER=$AGENT_ONE \
COUNTERPARTY=$PLAYER_ONE \
forge script script/SwapScripts.s.sol:ExecuteSwap \
  --rpc-url https://sepolia.base.org --broadcast -vvvv
```

**Output:**
```
Intent: 0xa59b96601aff4b29e7a35ffbe135f660f5ae34a1d74772f22f50648d43a8dffe
Status: 2
Executed! New status: 3
```

### Utility Commands

```bash
# Check swap status (0=None, 1=Proposed, 2=Ready, 3=Executed, 4=Cancelled)
INTENT_HASH=0x... \
forge script script/SwapScripts.s.sol:CheckStatus \
  --rpc-url https://sepolia.base.org

# Check token balances
cast call 0x17abd6d0355cB2B933C014133B14245412ca00B6 \
  "balanceOf(address)(uint256)" $AGENT_ONE \
  --rpc-url https://sepolia.base.org

cast call 0xddFaC73904FE867B5526510E695826f4968A2357 \
  "balanceOf(address)(uint256)" $PLAYER_ONE \
  --rpc-url https://sepolia.base.org

# Check ETH balance (for gas)
cast balance $PLAYER_ONE --rpc-url https://sepolia.base.org
```

### Custom Swap Amounts

Default is 100 USDC for 0.1 WETH. Override with raw values:

```bash
PRIVATE_KEY=$AGENT_ONE_PK \
COUNTERPARTY=$PLAYER_ONE \
USDC_AMOUNT=50000000 \
WETH_AMOUNT=50000000000000000 \
forge script script/SwapScripts.s.sol:ProposeSwap \
  --rpc-url https://sepolia.base.org --broadcast -vvvv
```

Note: USDC has 6 decimals, WETH has 18 decimals.

## Deployment

### Deploy Your Own Contracts

```bash
# Configure
cp .env.example .env
# Edit: PRIVATE_KEY, AGENT_ONE, PLAYER_ONE, BASESCAN_API_KEY

# Deploy AtomicSwap + mock tokens + fund test accounts
make deploy-swap-mocks

# Or deploy just AtomicSwap (production)
make deploy-swap

# Or deploy mock tokens only (if AtomicSwap already exists)
ATOMIC_SWAP=0x... make deploy-mocks-only
```

## Usage

### Solidity: Inherit ERC8001

```solidity
import {ERC8001} from "@erc8001/sdk/contracts/ERC8001.sol";

contract MyCoordinator is ERC8001 {
    constructor() ERC8001("MyCoordinator", "1") {}

    function _executeCoordination(
        bytes32 intentHash,
        CoordinationPayload calldata payload,
        bytes calldata executionData
    ) internal override {
        // Your execution logic here
    }
}
```

### TypeScript: Sign Intents

```typescript
import { ERC8001Signer, buildERC8001Domain, fromViemWallet } from '@erc8001/sdk';
import { createWalletClient, http } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { baseSepolia } from 'viem/chains';

// Create wallet
const account = privateKeyToAccount('0x...');
const walletClient = createWalletClient({
  account,
  chain: baseSepolia,
  transport: http(),
});

// Create signer
const domain = buildERC8001Domain({
  name: 'AtomicSwap',
  version: '1',
  chainId: baseSepolia.id,
  verifyingContract: '0xD25FaF692736b74A674c8052F904b5C77f9cb2Ed',
});

const signer = new ERC8001Signer(fromViemWallet(walletClient), domain);

// Sign an intent
const { intent, payload, signature } = await signer.signIntent({
  coordinationType: SWAP_TYPE,
  participants: [alice, bob],
  coordinationData: swapTerms,
  nonce: 1n,
  expirySeconds: 3600,
});

// Sign an acceptance
const { attestation, signature: acceptSig } = await signer.signAcceptance(
  intentHash,
  3600
);
```

### HTML/JavaScript Frontend

A standalone HTML frontend is available at `examples/atomic-swap.html`. Just open in a browser - no build step required.

## Architecture

```
┌─────────────────────────────────────────────┐
│              User / Principal               │
└──────────────────┬──────────────────────────┘
                   │ signs intents
                   ▼
┌─────────────────────────────────────────────┐
│           TypeScript SDK                    │
│  • ERC8001Signer                            │
│  • BoundedExecutorSigner                    │
│  • EIP-712 utilities                        │
└──────────────────┬──────────────────────────┘
                   │ submits to chain
                   ▼
┌─────────────────────────────────────────────┐
│         ERC-8001 Coordinator                │
│  • Propose / Accept / Execute               │
│  • Multi-party consensus                    │
└──────────────────┬──────────────────────────┘
                   │ optional constraints
                   ▼
┌─────────────────────────────────────────────┐
│       BoundedAgentExecutor                  │
│  • Policy Merkle tree                       │
│  • Daily budget limits                      │
│  • Timelock governance                      │
└─────────────────────────────────────────────┘
```

## Project Structure

```
erc8001-sdk/
├── src/
│   ├── contracts/
│   │   ├── ERC8001.sol              # Base coordination contract
│   │   ├── interfaces/
│   │   │   ├── IERC8001.sol         # Interface
│   │   │   └── IBoundedAgentExecutor.sol
│   │   ├── execution/
│   │   │   └── BoundedAgentExecutor.sol  # Budget + policy constraints
│   │   └── examples/
│   │       └── AtomicSwap.sol       # Hello World example
│   └── ts/
│       ├── index.ts                 # Main exports
│       ├── types.ts                 # TypeScript types
│       ├── eip712.ts                # EIP-712 definitions
│       ├── utils.ts                 # Hash functions, builders
│       └── signer.ts                # High-level signing API
├── test/
│   └── AtomicSwap.t.sol             # Foundry tests
├── script/
│   ├── DeployAtomicSwap.s.sol       # Deployment scripts
│   └── SwapScripts.s.sol            # Propose/Accept/Execute scripts
├── examples/
│   ├── atomic-swap.ts               # TypeScript usage example
│   └── atomic-swap.html             # Standalone HTML frontend
├── foundry.toml
├── package.json
├── Makefile
└── HELLO_WORLD.md                   # Detailed Hello World guide
```

## Use Cases

| Use Case | Participants | What They're Coordinating |
|----------|--------------|---------------------------|
| **Atomic Swap** | 2 traders | "I'll give you X if you give me Y" |
| **Escrow** | buyer + seller | "Release funds when delivered" |
| **Group Bet** | N players | "We all agree to these terms" |
| **Service Agreement** | agent + provider | "I'll pay X for service Y" |
| **Multi-agent Task** | N agents | "We all commit to this action" |
| **Split Payment** | N payers | "We each contribute to this" |

## Make Commands

```bash
make build              # Compile contracts
make test               # Run tests
make test-gas           # Run tests with gas report
make deploy-swap        # Deploy AtomicSwap (with verification)
make deploy-swap-mocks  # Deploy + mock tokens + fund accounts
make deploy-mocks-only  # Deploy mock tokens only
make deploy-swap-dry    # Simulate deployment
make install            # Install Foundry dependencies
make help               # Show all commands
```

## Security

This code is unaudited. Use at your own risk.

Key security properties:
- **EIP-712 signatures**: Prevents cross-domain replay attacks
- **Nonce management**: Prevents replay of intents
- **Expiry timestamps**: Limits validity window
- **Policy trees**: Restricts allowed operations (BoundedAgentExecutor)
- **Budget limits**: Caps daily exposure per agent
- **Timelocked governance**: Prevents instant policy changes
- **Guardian veto**: Emergency protection

## License

MIT

## Links

- [ERC-8001 Specification](https://eips.ethereum.org/EIPS/eip-8001)
- [Hello World Guide](./HELLO_WORLD.md)
- [Base Sepolia Faucet](https://www.alchemy.com/faucets/base-sepolia)
- [BaseScan (Testnet)](https://sepolia.basescan.org)