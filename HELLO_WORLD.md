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
| **Permissionless** | Anyone can execute once all parties sign |
| **Auditable** | On-chain proof of every party's consent |
| **Cancellable** | Proposer can cancel; anyone can cancel after expiry |
| **Time-bounded** | Intent and each acceptance carry independent expiries |
| **Canonical** | Participants must be unique and strictly ascending by address |

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
    // EIP-712 domain is hardcoded to {name: "ERC-8001", version: "1"}
    constructor() ERC8001() {}

    function _executeCoordinationHook(
        bytes32 intentHash,
        CoordinationPayload calldata payload,
        bytes calldata executionData
    ) internal override returns (bool success, bytes memory result) {
        // Decode the swap terms from the payload
        SwapTerms memory terms = abi.decode(
            payload.coordinationData,
            (SwapTerms)
        );

        // Participants are stored in the coordination state, not the payload.
        // The proposer is always coord.proposer; the other party is the other participant.
        CoordinationState storage coord = _getCoordination(intentHash);
        address partyA = coord.proposer;
        address partyB = coord.participants[0] == partyA
            ? coord.participants[1]
            : coord.participants[0];

        // Atomic swap: both transfers or revert
        IERC20(terms.tokenA).safeTransferFrom(partyA, partyB, terms.amountA);
        IERC20(terms.tokenB).safeTransferFrom(partyB, partyA, terms.amountB);

        return (true, "");
    }
}
```

That's it. The base `ERC8001` contract handles:
- Intent creation, EIP-712 signature verification, and nonce replay protection
- Participant canonicalization (strictly ascending addresses, proposer must be included)
- Per-acceptance expiry tracking — each acceptance can expire independently
- Status management (`Proposed → Ready → Executed`; `Expired` returned dynamically)
- Cancellation — proposer only before expiry, anyone after expiry
- `getCoordinationStatus` returns the full tuple: status, proposer, participants, acceptedBy, expiry

You just implement `_executeCoordinationHook` with your business logic.

### TypeScript: Sign and Submit

```typescript
import { ERC8001Signer, buildERC8001Domain, fromViemWallet, sortParticipants } from '@erc8001/sdk';

// Domain is always {name: "ERC-8001", version: "1"} per the spec
const domain = buildERC8001Domain({ chainId, verifyingContract: SWAP_ADDRESS });

// Alice proposes — participants sorted ascending by address (required by spec)
const { intent, payload, signature } = await aliceSigner.signIntent({
  coordinationType: SWAP_TYPE,
  participants: sortParticipants([alice, bob]),
  coordinationData: encodeSwapTerms(USDC, 100e6, WETH, 0.05e18),
  nonce: 1n,
});

// New param order: (intent, signature, payload)
const intentHash = await swapContract.proposeCoordination(intent, signature, payload);

// Bob accepts — signature is now embedded inside AcceptanceAttestation
// acceptCoordination requires msg.sender == attestation.participant
const { attestation } = await bobSigner.signAcceptance(
  intentHash,
  bob,   // participant
  1n,    // nonce
  3600   // expiry seconds
);
await swapContract.acceptCoordination(intentHash, attestation); // returns bool allAccepted

// Execute — returns (bool success, bytes memory result)
const [success, result] = await swapContract.executeCoordination(intentHash, payload, '0x');
```

## What If...

**Bob never accepts?**
→ Nothing happens. Alice's tokens stay in her wallet.

**The intent expires?**
→ `getCoordinationStatus` returns `Expired` dynamically. Execution reverts. Anyone can call `cancelCoordination` to clean up. Alice can then propose a new one.

**Alice changes her mind?**
→ She can cancel any time before the intent expires. After expiry, anyone can cancel on her behalf.

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
