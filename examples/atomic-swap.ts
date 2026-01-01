/**
 * ERC-8001 Hello World: Atomic Swap
 * 
 * This example shows how to coordinate a trustless token swap
 * between Alice and Bob using the ERC-8001 SDK.
 */

import {
  ERC8001Signer,
  buildERC8001Domain,
  fromViemWallet,
  hashAgentIntent,
  type Address,
  type Hex,
} from '@erc8001/sdk';
import { 
  createWalletClient, 
  createPublicClient,
  http, 
  encodeFunctionData,
  parseAbi,
  encodeAbiParameters,
  keccak256,
  encodePacked,
} from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { baseSepolia } from 'viem/chains';

// ═══════════════════════════════════════════════════════════════════════════
// CONFIGURATION
// ═══════════════════════════════════════════════════════════════════════════

const SWAP_CONTRACT = '0x...' as Address; // Your deployed AtomicSwap address
const USDC = '0x...' as Address;
const WETH = '0x...' as Address;

const SWAP_TYPE = keccak256(encodePacked(['string'], ['ATOMIC_SWAP_V1']));
const PAYLOAD_VERSION = keccak256(encodePacked(['string'], ['V1']));

// ═══════════════════════════════════════════════════════════════════════════
// STEP 1: SETUP SIGNERS
// ═══════════════════════════════════════════════════════════════════════════

async function setupSigners() {
  // In production, these would come from user wallets (MetaMask, etc.)
  const aliceAccount = privateKeyToAccount('0x...');
  const bobAccount = privateKeyToAccount('0x...');

  const aliceWallet = createWalletClient({
    account: aliceAccount,
    chain: baseSepolia,
    transport: http(),
  });

  const bobWallet = createWalletClient({
    account: bobAccount,
    chain: baseSepolia,
    transport: http(),
  });

  // Create ERC-8001 signers
  const domain = buildERC8001Domain({
    name: 'AtomicSwap',
    version: '1',
    chainId: baseSepolia.id,
    verifyingContract: SWAP_CONTRACT,
  });

  const aliceSigner = new ERC8001Signer(fromViemWallet(aliceWallet), domain);
  const bobSigner = new ERC8001Signer(fromViemWallet(bobWallet), domain);

  return { aliceSigner, bobSigner, aliceAccount, bobAccount };
}

// ═══════════════════════════════════════════════════════════════════════════
// STEP 2: ALICE PROPOSES A SWAP
// ═══════════════════════════════════════════════════════════════════════════

async function aliceProposes(
  aliceSigner: ERC8001Signer,
  alice: Address,
  bob: Address
) {
  console.log('🔷 Step 1: Alice proposes a swap');
  console.log('   Alice offers: 100 USDC');
  console.log('   Alice wants:  0.05 WETH');

  // Encode the swap terms
  const swapTerms = encodeAbiParameters(
    [
      { type: 'address', name: 'tokenA' },
      { type: 'uint256', name: 'amountA' },
      { type: 'address', name: 'tokenB' },
      { type: 'uint256', name: 'amountB' },
    ],
    [
      USDC,
      100_000_000n, // 100 USDC (6 decimals)
      WETH,
      50_000_000_000_000_000n, // 0.05 WETH (18 decimals)
    ]
  );

  // Sign the intent
  const { intent, payload, signature } = await aliceSigner.signIntent({
    coordinationType: SWAP_TYPE,
    participants: [alice, bob],
    coordinationData: swapTerms,
    nonce: 1n,
    expirySeconds: 3600, // 1 hour
    version: PAYLOAD_VERSION,
  });

  console.log('   ✅ Alice signed the intent');
  
  return { intent, payload, signature };
}

// ═══════════════════════════════════════════════════════════════════════════
// STEP 3: BOB REVIEWS AND ACCEPTS
// ═══════════════════════════════════════════════════════════════════════════

async function bobAccepts(
  bobSigner: ERC8001Signer,
  intentHash: Hex
) {
  console.log('\n🔷 Step 2: Bob reviews and accepts');
  
  // In a real app, Bob would see the swap terms in a UI
  // and decide whether to accept
  console.log('   Bob sees: "Trade 0.05 WETH for 100 USDC"');
  console.log('   Bob decides: "Good deal!"');

  const { attestation, signature } = await bobSigner.signAcceptance(
    intentHash,
    3600 // 1 hour expiry
  );

  console.log('   ✅ Bob signed the acceptance');
  
  return { attestation, signature };
}

// ═══════════════════════════════════════════════════════════════════════════
// STEP 4: EXECUTE THE SWAP
// ═══════════════════════════════════════════════════════════════════════════

async function executeSwap(
  intentHash: Hex,
  payload: any
) {
  console.log('\n🔷 Step 3: Execute the swap');
  console.log('   Anyone can call execute now that both parties signed');

  // This would be a contract call
  // await swapContract.executeCoordination(intentHash, payload, '0x');

  console.log('   ✅ Swap executed!');
  console.log('\n📊 Result:');
  console.log('   Alice: -100 USDC, +0.05 WETH');
  console.log('   Bob:   +100 USDC, -0.05 WETH');
}

// ═══════════════════════════════════════════════════════════════════════════
// MAIN FLOW
// ═══════════════════════════════════════════════════════════════════════════

async function main() {
  console.log('═══════════════════════════════════════════════════════════');
  console.log('         ERC-8001 Hello World: Atomic Swap');
  console.log('═══════════════════════════════════════════════════════════\n');

  // Setup
  const { aliceSigner, bobSigner, aliceAccount, bobAccount } = await setupSigners();
  const alice = aliceAccount.address;
  const bob = bobAccount.address;

  // Step 1: Alice proposes
  const { intent, payload, signature: aliceSig } = await aliceProposes(
    aliceSigner,
    alice,
    bob
  );

  // Calculate intent hash (this would come from the contract in reality)
  const intentHash = hashAgentIntent(intent);
  console.log(`   Intent hash: ${intentHash.slice(0, 18)}...`);

  // Step 2: Bob accepts
  const { attestation, signature: bobSig } = await bobAccepts(bobSigner, intentHash);

  // Step 3: Execute
  await executeSwap(intentHash, payload);

  console.log('\n═══════════════════════════════════════════════════════════');
  console.log('                    SWAP COMPLETE!');
  console.log('═══════════════════════════════════════════════════════════');
}

// Run the example
main().catch(console.error);


// ═══════════════════════════════════════════════════════════════════════════
// ALTERNATIVE: SIMPLER API (what the SDK could provide)
// ═══════════════════════════════════════════════════════════════════════════

/**
 * With a higher-level SDK, the flow could be even simpler:
 * 
 * ```typescript
 * import { AtomicSwapClient } from '@erc8001/sdk/atomic-swap';
 * 
 * const swap = new AtomicSwapClient(swapContract, aliceWallet);
 * 
 * // Alice proposes
 * const proposal = await swap.propose({
 *   offer: { token: USDC, amount: 100n * 10n**6n },
 *   want: { token: WETH, amount: 50n * 10n**15n },
 *   counterparty: bob,
 * });
 * 
 * // Bob accepts (from Bob's client)
 * await swap.accept(proposal.intentHash);
 * 
 * // Anyone executes
 * await swap.execute(proposal.intentHash);
 * ```
 */
