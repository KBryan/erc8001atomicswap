# ERC-8001 AtomicSwap Tutorial

A step-by-step guide to building trustless multi-party coordination on Ethereum.

## Table of Contents

1. [Introduction](#introduction)
2. [Prerequisites](#prerequisites)
3. [Understanding the Flow](#understanding-the-flow)
4. [Setup](#setup)
5. [Part 1: Your First Atomic Swap](#part-1-your-first-atomic-swap)
6. [Part 2: Understanding What Happened](#part-2-understanding-what-happened)
7. [Part 3: Using the Frontend](#part-3-using-the-frontend)
8. [Part 4: Building Your Own Coordinator](#part-4-building-your-own-coordinator)
9. [Troubleshooting](#troubleshooting)
10. [Next Steps](#next-steps)

---

## Introduction

### What is ERC-8001?

ERC-8001 is an Ethereum standard for **multi-party coordination**. It provides a simple primitive:

```
Propose → Accept → Execute
```

Multiple parties cryptographically sign their agreement, and only when everyone has agreed does the action execute.

### Why Does This Matter?

Imagine you want to swap tokens with someone you don't trust:

**Without ERC-8001:**
- You send first → they might not send back
- They send first → you might not send back
- Use a trusted escrow → you both trust the escrow
- Use a DEX → pay fees, limited to listed pairs

**With ERC-8001:**
- Alice proposes: "I'll give 100 USDC for 0.1 WETH"
- Bob accepts: "I agree to those terms"
- Anyone executes: Both transfers happen atomically
- If Bob never accepts → Alice's funds stay safe
- No intermediary, no fees (just gas), no trust required

### The AtomicSwap Example

This tutorial uses AtomicSwap as the "Hello World" of ERC-8001. It's the simplest possible coordinator - two parties exchanging tokens.

---

## Prerequisites

### Required Tools

1. **Foundry** - Ethereum development toolkit
   ```bash
   curl -L https://foundry.paradigm.xyz | bash
   foundryup
   ```

2. **Git** - Version control
   ```bash
   # macOS
   brew install git
   
   # Ubuntu
   sudo apt install git
   ```

3. **A code editor** - VS Code recommended

### Required Accounts

You need **two Ethereum accounts** with:
- Private keys you control
- Some Base Sepolia ETH for gas (~0.01 ETH each)

**Get testnet ETH:**
- [Alchemy Faucet](https://www.alchemy.com/faucets/base-sepolia)
- [QuickNode Faucet](https://faucet.quicknode.com/base/sepolia)

### Knowledge Assumptions

- Basic command line usage
- Understanding of Ethereum transactions
- Familiarity with ERC-20 tokens

---

## Understanding the Flow

Before we start, let's understand what we're building:

```
┌─────────────────────────────────────────────────────────────────┐
│                        ATOMIC SWAP FLOW                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  SETUP (one-time)                                               │
│  ┌─────────┐          ┌─────────┐                              │
│  │  Alice  │          │   Bob   │                              │
│  │ 100 USDC│          │ 0.1 WETH│                              │
│  └────┬────┘          └────┬────┘                              │
│       │                    │                                    │
│       ▼                    ▼                                    │
│  [Approve USDC]       [Approve WETH]                           │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  STEP 1: PROPOSE                                                │
│  ┌─────────┐                                                   │
│  │  Alice  │──▶ "I offer 100 USDC for 0.1 WETH from Bob"       │
│  └─────────┘         │                                         │
│                      ▼                                          │
│              [Signs EIP-712 Intent]                            │
│                      │                                          │
│                      ▼                                          │
│              [Submit to Chain]                                 │
│                      │                                          │
│                      ▼                                          │
│              Intent Hash: 0xabc123...                          │
│              Status: PROPOSED (1)                              │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  STEP 2: ACCEPT                                                 │
│  ┌─────────┐                                                   │
│  │   Bob   │──▶ "I accept intent 0xabc123..."                  │
│  └─────────┘         │                                         │
│                      ▼                                          │
│              [Signs EIP-712 Acceptance]                        │
│                      │                                          │
│                      ▼                                          │
│              [Submit to Chain]                                 │
│                      │                                          │
│                      ▼                                          │
│              Status: READY (2)                                 │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  STEP 3: EXECUTE                                                │
│  ┌─────────┐                                                   │
│  │ Anyone  │──▶ "Execute intent 0xabc123..."                   │
│  └─────────┘         │                                         │
│                      ▼                                          │
│              [AtomicSwap Contract]                             │
│                      │                                          │
│              ┌───────┴───────┐                                 │
│              ▼               ▼                                  │
│       [Transfer USDC]  [Transfer WETH]                         │
│       Alice → Bob      Bob → Alice                             │
│              │               │                                  │
│              └───────┬───────┘                                 │
│                      │                                          │
│              BOTH SUCCEED OR BOTH FAIL                         │
│                      │                                          │
│                      ▼                                          │
│              Status: EXECUTED (3)                              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Key insight:** Neither party risks their funds. Alice's USDC only moves if Bob's WETH moves in the same transaction.

---

## Setup

### 1. Clone the Repository

```bash
git clone https://github.com/anthropic/erc8001-sdk
cd erc8001-sdk
```

### 2. Install Dependencies

```bash
make install
```

### 3. Configure Environment

```bash
cp .env.example .env
```

Edit `.env` with your values:

```bash
# Your deployer/main private key
PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# Alice's private key (will swap USDC for WETH)
AGENT_ONE_PK=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d

# Bob's private key (will swap WETH for USDC)  
PLAYER_ONE_PK=0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a

# Derive addresses
AGENT_ONE=0x70997970C51812dc3A010C7d01b50e0d17dc79C8
PLAYER_ONE=0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC
```

**Note:** These are example keys. NEVER use these in production!

To derive address from private key:
```bash
cast wallet address 0xYOUR_PRIVATE_KEY
```

### 4. Build and Test

```bash
make build
make test
```

You should see all tests passing.

---

## Part 1: Your First Atomic Swap

Let's execute a real swap on Base Sepolia testnet!

### Using Deployed Contracts

We have contracts already deployed:

| Contract | Address |
|----------|---------|
| AtomicSwap | `0xD25FaF692736b74A674c8052F904b5C77f9cb2Ed` |
| Mock USDC | `0x17abd6d0355cB2B933C014133B14245412ca00B6` |
| Mock WETH | `0xddFaC73904FE867B5526510E695826f4968A2357` |

### Step 0: Get Test Tokens

First, mint some test tokens to your accounts:

```bash
# Load environment
source .env

# Mint 1000 USDC to Alice (AGENT_ONE)
cast send 0x17abd6d0355cB2B933C014133B14245412ca00B6 \
  "mint(address,uint256)" \
  $AGENT_ONE \
  1000000000 \
  --private-key $PRIVATE_KEY \
  --rpc-url https://sepolia.base.org

# Mint 1 WETH to Bob (PLAYER_ONE)
cast send 0xddFaC73904FE867B5526510E695826f4968A2357 \
  "mint(address,uint256)" \
  $PLAYER_ONE \
  1000000000000000000 \
  --private-key $PRIVATE_KEY \
  --rpc-url https://sepolia.base.org
```

Verify balances:

```bash
# Alice's USDC (should be 1000000000 = 1000 USDC)
cast call 0x17abd6d0355cB2B933C014133B14245412ca00B6 \
  "balanceOf(address)(uint256)" $AGENT_ONE \
  --rpc-url https://sepolia.base.org

# Bob's WETH (should be 1000000000000000000 = 1 WETH)
cast call 0xddFaC73904FE867B5526510E695826f4968A2357 \
  "balanceOf(address)(uint256)" $PLAYER_ONE \
  --rpc-url https://sepolia.base.org
```

### Step 1: Approve Tokens

Before swapping, each party must approve the AtomicSwap contract to move their tokens:

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

### Step 2: Alice Proposes the Swap

```bash
PRIVATE_KEY=$AGENT_ONE_PK \
COUNTERPARTY=$PLAYER_ONE \
forge script script/SwapScripts.s.sol:ProposeSwap \
  --rpc-url https://sepolia.base.org --broadcast -vvvv
```

**Output:**
```
Proposer: 0x70997970C51812dc3A010C7d01b50e0d17dc79C8
Counterparty: 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC
Intent Hash: 0x1234567890abcdef...
```

🔴 **Important:** Copy the Intent Hash! You'll need it for the next steps.

### Step 3: Bob Accepts the Swap

```bash
PRIVATE_KEY=$PLAYER_ONE_PK \
INTENT_HASH=0x1234567890abcdef... \
forge script script/SwapScripts.s.sol:AcceptSwap \
  --rpc-url https://sepolia.base.org --broadcast -vvvv
```

**Output:**
```
Acceptor: 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC
Intent: 0x1234567890abcdef...
Status: 1
Accepted! New status: 2
```

Status changed from 1 (Proposed) to 2 (Ready)!

### Step 4: Execute the Swap

Anyone can execute once it's Ready:

```bash
PRIVATE_KEY=$AGENT_ONE_PK \
INTENT_HASH=0x1234567890abcdef... \
PROPOSER=$AGENT_ONE \
COUNTERPARTY=$PLAYER_ONE \
forge script script/SwapScripts.s.sol:ExecuteSwap \
  --rpc-url https://sepolia.base.org --broadcast -vvvv
```

**Output:**
```
Intent: 0x1234567890abcdef...
Status: 2
Executed! New status: 3
```

### Step 5: Verify the Swap

Check the new balances:

```bash
# Alice's USDC (should be 900 USDC less)
cast call 0x17abd6d0355cB2B933C014133B14245412ca00B6 \
  "balanceOf(address)(uint256)" $AGENT_ONE \
  --rpc-url https://sepolia.base.org

# Alice's WETH (should have 0.1 WETH now!)
cast call 0xddFaC73904FE867B5526510E695826f4968A2357 \
  "balanceOf(address)(uint256)" $AGENT_ONE \
  --rpc-url https://sepolia.base.org

# Bob's USDC (should have 100 USDC now!)
cast call 0x17abd6d0355cB2B933C014133B14245412ca00B6 \
  "balanceOf(address)(uint256)" $PLAYER_ONE \
  --rpc-url https://sepolia.base.org

# Bob's WETH (should be 0.9 WETH less)
cast call 0xddFaC73904FE867B5526510E695826f4968A2357 \
  "balanceOf(address)(uint256)" $PLAYER_ONE \
  --rpc-url https://sepolia.base.org
```

🎉 **Congratulations!** You just executed a trustless atomic swap!

---

## Part 2: Understanding What Happened

Let's break down what happened under the hood.

### EIP-712 Signatures

When Alice proposed, she signed an **EIP-712 typed data** message:

```solidity
struct AgentIntent {
    bytes32 payloadHash;      // Hash of swap terms
    uint64 expiry;            // When this intent expires
    uint64 nonce;             // Prevents replay
    address agentId;          // Alice's address
    bytes32 coordinationType; // SWAP_TYPE identifier
    uint256 coordinationValue;// Optional value (0 for swaps)
    address[] participants;   // [Alice, Bob]
}
```

This signature proves:
1. Alice agreed to these exact terms
2. Alice agreed at this specific time
3. This is for THIS contract on THIS chain
4. It can't be replayed (nonce)

### The Payload

The actual swap terms are in the payload:

```solidity
struct SwapTerms {
    address tokenA;   // USDC
    uint256 amountA;  // 100 (with decimals)
    address tokenB;   // WETH  
    uint256 amountB;  // 0.1 (with decimals)
}
```

The `payloadHash` in the intent commits Alice to these exact terms.

### Bob's Acceptance

Bob signed an **AcceptanceAttestation**:

```solidity
struct AcceptanceAttestation {
    bytes32 intentHash;  // The intent Bob is accepting
    uint64 expiry;       // When Bob's acceptance expires
    address agentId;     // Bob's address
}
```

This proves Bob agreed to Alice's specific proposal.

### Atomic Execution

The `_executeCoordination` function in AtomicSwap.sol:

```solidity
function _executeCoordination(
    bytes32 intentHash,
    CoordinationPayload calldata payload,
    bytes calldata
) internal override {
    // Decode swap terms
    SwapTerms memory terms = decodeSwapTerms(payload.coordinationData);
    
    address partyA = payload.participants[0]; // Alice
    address partyB = payload.participants[1]; // Bob

    // ATOMIC: Both transfers in one transaction
    IERC20(terms.tokenA).transferFrom(partyA, partyB, terms.amountA);
    IERC20(terms.tokenB).transferFrom(partyB, partyA, terms.amountB);
    
    // If either transfer fails, BOTH revert
}
```

**Why is this atomic?**

If the first transfer succeeds but the second fails, the entire transaction reverts. The EVM's atomicity guarantees both happen or neither happens.

### Status Flow

```
0: None      - Intent doesn't exist
1: Proposed  - Alice proposed, waiting for Bob
2: Ready     - Bob accepted, ready to execute
3: Executed  - Swap completed
4: Cancelled - Alice cancelled before Bob accepted
```

---

## Part 3: Using the Frontend

We've included a browser-based frontend for a visual experience.

### Running the Frontend

1. Open `examples/atomic-swap.html` in your browser
2. Connect MetaMask (switch to Base Sepolia)
3. The UI shows:
    - Your balances
    - Approve buttons
    - Propose/Accept/Execute tabs

### Frontend Flow

1. **As Alice:**
    - Connect wallet
    - Click "Approve USDC"
    - Enter Bob's address
    - Click "Propose Swap"
    - Copy the Intent Hash

2. **As Bob:**
    - Switch MetaMask to Bob's account
    - Refresh page, connect wallet
    - Click "Approve WETH"
    - Go to "Accept" tab
    - Paste Intent Hash
    - Click "Accept Swap"

3. **Execute:**
    - Go to "Execute" tab
    - Paste Intent Hash
    - Click "Execute Swap"

---

## Part 4: Building Your Own Coordinator

Now let's create your own ERC-8001 coordinator!

### Example: Group Bet

A simple bet where N players agree on an outcome:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC8001} from "../ERC8001.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract GroupBet is ERC8001 {
    bytes32 public constant BET_TYPE = keccak256("GROUP_BET_V1");
    
    struct BetTerms {
        address token;           // Token to bet with
        uint256 amountPerPlayer; // Each player's stake
        bytes32 conditionHash;   // Hash of bet condition
        address oracle;          // Who decides the winner
    }
    
    mapping(bytes32 => address) public winners;
    
    constructor() ERC8001("GroupBet", "1") {}
    
    function _executeCoordination(
        bytes32 intentHash,
        CoordinationPayload calldata payload,
        bytes calldata executionData
    ) internal override {
        BetTerms memory terms = abi.decode(
            payload.coordinationData, 
            (BetTerms)
        );
        
        // Collect stakes from all participants
        uint256 pot = 0;
        for (uint i = 0; i < payload.participants.length; i++) {
            IERC20(terms.token).transferFrom(
                payload.participants[i],
                address(this),
                terms.amountPerPlayer
            );
            pot += terms.amountPerPlayer;
        }
        
        // Winner set by oracle (in executionData)
        address winner = abi.decode(executionData, (address));
        require(isParticipant(payload.participants, winner), "Not a player");
        
        // Transfer pot to winner
        IERC20(terms.token).transfer(winner, pot);
        winners[intentHash] = winner;
    }
    
    function isParticipant(
        address[] memory participants, 
        address addr
    ) internal pure returns (bool) {
        for (uint i = 0; i < participants.length; i++) {
            if (participants[i] == addr) return true;
        }
        return false;
    }
}
```

### Key Points for Custom Coordinators

1. **Inherit ERC8001**
   ```solidity
   contract MyCoordinator is ERC8001 {
       constructor() ERC8001("MyCoordinator", "1") {}
   }
   ```

2. **Define your coordination type**
   ```solidity
   bytes32 public constant MY_TYPE = keccak256("MY_COORDINATION_V1");
   ```

3. **Implement `_executeCoordination`**
   ```solidity
   function _executeCoordination(
       bytes32 intentHash,
       CoordinationPayload calldata payload,
       bytes calldata executionData
   ) internal override {
       // Your logic here
   }
   ```

4. **Define your terms struct**
   ```solidity
   struct MyTerms {
       // Your coordination parameters
   }
   ```

5. **Encode/decode helpers**
   ```solidity
   function encodeTerms(...) public pure returns (bytes memory) {
       return abi.encode(MyTerms({...}));
   }
   
   function decodeTerms(bytes memory data) public pure returns (MyTerms memory) {
       return abi.decode(data, (MyTerms));
   }
   ```

---

## Troubleshooting

### "NotParticipant" Error

**Problem:** The signer isn't in the participants list.

**Solution:** Check that:
- You're using the correct private key
- The address matches what's in the intent
- Run `cast wallet address $YOUR_PK` to verify

### "AlreadyAccepted" Error

**Problem:** Trying to accept an intent that's already been accepted.

**Solution:**
- Check status with `CheckStatus` script
- If status is 2 (Ready), proceed to execute
- If status is 3 (Executed), the swap is done

### "InsufficientAllowance" or Transfer Fails

**Problem:** Token approval not set.

**Solution:**
```bash
# Check allowance
cast call <TOKEN_ADDRESS> \
  "allowance(address,address)(uint256)" \
  <YOUR_ADDRESS> \
  0xD25FaF692736b74A674c8052F904b5C77f9cb2Ed \
  --rpc-url https://sepolia.base.org

# If 0, run approve script
```

### "Insufficient funds for gas"

**Problem:** Account has no ETH for gas.

**Solution:**
```bash
# Check balance
cast balance $YOUR_ADDRESS --rpc-url https://sepolia.base.org

# Get testnet ETH from faucet
# https://www.alchemy.com/faucets/base-sepolia
```

### "Stack too deep" Compilation Error

**Problem:** Solidity compiler limitation.

**Solution:** Use `--via-ir` flag or refactor code to use fewer local variables.

---

## Next Steps

### 1. Try Different Swap Amounts

```bash
USDC_AMOUNT=50000000 \        # 50 USDC
WETH_AMOUNT=25000000000000000 \ # 0.025 WETH
forge script script/SwapScripts.s.sol:ProposeSwap ...
```

### 2. Build a Custom Coordinator

Ideas:
- **Escrow**: Release payment on delivery confirmation
- **Dutch Auction**: Price decreases until someone accepts
- **Multi-sig Action**: N-of-M approval for operations
- **Service Agreement**: Pay for completed work

### 3. Add to Your Project

```bash
forge install your-org/erc8001-sdk
```

```solidity
import {ERC8001} from "erc8001-sdk/contracts/ERC8001.sol";
```

### 4. Read the Specification

Full ERC-8001 spec: [EIP-8001](https://eips.ethereum.org/EIPS/eip-8001)

### 5. Join the Community

- GitHub Issues for questions
- Submit PRs for improvements
- Share what you build!

---

## Summary

You've learned:

✅ What ERC-8001 solves (trustless multi-party coordination)

✅ The Propose → Accept → Execute flow

✅ How to execute an atomic swap with Foundry

✅ What happens under the hood (EIP-712, atomicity)

✅ How to build your own coordinator

**The key insight:** ERC-8001 provides a standard primitive for "everyone agrees, then execute." This simple pattern enables countless trustless interactions between parties who don't need to trust each other.

---

## Quick Reference

### Contract Addresses (Base Sepolia)

```
AtomicSwap: 0xD25FaF692736b74A674c8052F904b5C77f9cb2Ed
Mock USDC:  0x17abd6d0355cB2B933C014133B14245412ca00B6
Mock WETH:  0xddFaC73904FE867B5526510E695826f4968A2357
```

### Commands Cheatsheet

```bash
# Approve
PRIVATE_KEY=$AGENT_ONE_PK forge script script/SwapScripts.s.sol:ApproveUSDC --rpc-url https://sepolia.base.org --broadcast
PRIVATE_KEY=$PLAYER_ONE_PK forge script script/SwapScripts.s.sol:ApproveWETH --rpc-url https://sepolia.base.org --broadcast

# Propose
PRIVATE_KEY=$AGENT_ONE_PK COUNTERPARTY=$PLAYER_ONE forge script script/SwapScripts.s.sol:ProposeSwap --rpc-url https://sepolia.base.org --broadcast -vvvv

# Accept
PRIVATE_KEY=$PLAYER_ONE_PK INTENT_HASH=0x... forge script script/SwapScripts.s.sol:AcceptSwap --rpc-url https://sepolia.base.org --broadcast -vvvv

# Execute
PRIVATE_KEY=$AGENT_ONE_PK INTENT_HASH=0x... PROPOSER=$AGENT_ONE COUNTERPARTY=$PLAYER_ONE forge script script/SwapScripts.s.sol:ExecuteSwap --rpc-url https://sepolia.base.org --broadcast -vvvv

# Check Status
INTENT_HASH=0x... forge script script/SwapScripts.s.sol:CheckStatus --rpc-url https://sepolia.base.org

# Check Balances
cast call 0x17abd6d0355cB2B933C014133B14245412ca00B6 "balanceOf(address)(uint256)" $ADDRESS --rpc-url https://sepolia.base.org
```

### Status Codes

| Code | Status | Meaning |
|------|--------|---------|
| 0 | None | Intent doesn't exist |
| 1 | Proposed | Waiting for acceptance |
| 2 | Ready | All parties accepted, can execute |
| 3 | Executed | Coordination completed |
| 4 | Cancelled | Proposer cancelled |

---

*Happy building! 🚀*