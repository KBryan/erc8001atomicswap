# ERC-8001 Hello World: Atomic Swap

## The Problem

Alice has 100 USDC. Bob has 0.05 WETH. They want to trade.

**Without ERC-8001:**
- Trust a centralized exchange?  Fees, custody risk
- Use a DEX?  Gas costs, slippage, MEV
- Send first and hope?  Counterparty risk

**With ERC-8001:**
- Alice proposes the swap (signs an intent)
- Bob reviews and accepts (signs an acceptance)
- Swap executes atomically
- No intermediary. No trust. No counterparty risk.

## The Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│   1. PROPOSE                                                    │
│   ─────────                                                     │
│   Alice: "I'll give 100 USDC for 0.05 WETH"                    │
│   Alice signs → Intent created                                  │
│                                                                 │
│   2. ACCEPT                                                     │
│   ────────                                                      │
│   Bob sees the offer, likes it                                  │
│   Bob signs → Coordination is READY                             │
│                                                                 │
│   3. EXECUTE                                                    │
│   ─────────                                                     │
│   Anyone calls execute()                                        │
│   Tokens swap atomically                                        │
│                                                                 │
│   Alice: -100 USDC, +0.05 WETH                               │
│   Bob:   +100 USDC, -0.05 WETH                               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Key Properties

| Property | What it means |
|----------|---------------|
| **Atomic** | Both transfers happen or neither does |
| **Trustless** | No intermediary holds funds |
| **Permissionless** | Anyone can execute once both sign |
| **Auditable** | On-chain proof of both parties' consent |
| **Cancellable** | Proposer can cancel before execution |
| **Time-bounded** | Intent expires if not executed |

## Run the Example

```bash
# Install dependencies
forge install

# Run the test
forge test --match-contract AtomicSwapTest -vvv
```

## The Code

### Contract: `AtomicSwap.sol`

```solidity
contract AtomicSwap is ERC8001 {
    
    function _executeCoordination(
        bytes32 intentHash,
        CoordinationPayload calldata payload,
        bytes calldata executionData
    ) internal override {
        // Decode the swap terms
        SwapTerms memory terms = abi.decode(
            payload.coordinationData, 
            (SwapTerms)
        );

        address partyA = payload.participants[0];
        address partyB = payload.participants[1];

        // Atomic swap: both transfers or revert
        IERC20(terms.tokenA).safeTransferFrom(partyA, partyB, terms.amountA);
        IERC20(terms.tokenB).safeTransferFrom(partyB, partyA, terms.amountB);
    }
}
```

That's it. The base `ERC8001` contract handles:
- Intent creation and validation
- EIP-712 signature verification
- Acceptance tracking
- Status management (Proposed → Ready → Executed)
- Expiry and nonce handling
- Cancellation

You just implement `_executeCoordination` with your business logic.

### TypeScript: Sign and Submit

```typescript
import { ERC8001Signer, fromViemWallet } from '@erc8001/sdk';

// Alice proposes
const { intent, payload, signature } = await aliceSigner.signIntent({
  coordinationType: SWAP_TYPE,
  participants: [alice, bob],
  coordinationData: encodeSwapTerms(USDC, 100e6, WETH, 0.05e18),
  nonce: 1n,
});

// Submit to chain
const intentHash = await swapContract.proposeCoordination(intent, payload, signature);

// Bob accepts
const { attestation, signature: bobSig } = await bobSigner.signAcceptance(intentHash);
await swapContract.acceptCoordination(intentHash, attestation, bobSig);

// Execute
await swapContract.executeCoordination(intentHash, payload, '0x');
```

## What If...

**Bob never accepts?**
→ Nothing happens. Alice's tokens stay in her wallet.

**The intent expires?**
→ Can't execute. Alice can propose a new one.

**Alice changes her mind?**
→ She can cancel before Bob accepts.

**Bob accepts but no one executes?**
→ Anyone can execute. Set up a keeper, or execute yourself.

**Someone tries to execute with wrong terms?**
→ Payload hash mismatch. Reverts.

## Why Not Just Use Uniswap?

| | ERC-8001 Swap | Uniswap |
|---|---|---|
| **Price** | You set it | Market determines |
| **Counterparty** | Specific person | Liquidity pool |
| **Slippage** | Zero | Can be significant |
| **MEV** | Not applicable | Sandwich attacks |
| **Use case** | OTC, known parties | Public trading |

ERC-8001 is for **coordination between known parties**, not public trading.

## Other Use Cases

The same pattern works for:

- **Escrow**: "Release funds when I confirm delivery"
- **Multi-sig**: "Transfer only if 2/3 signers agree"
- **Bets**: "Loser pays winner based on oracle"
- **Service agreements**: "I'll pay X for service Y"
- **Group purchases**: "We all chip in for this"

The pattern is always:
1. Propose terms
2. Required parties accept
3. Execute when ready

## Next Steps

- Read the [ERC-8001 spec](https://eips.ethereum.org/EIPS/eip-8001)
- Check out [BoundedAgentExecutor](./src/contracts/execution/BoundedAgentExecutor.sol) for adding budget limits
- Build your own coordination contract!
