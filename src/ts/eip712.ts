/**
 * EIP-712 Type Definitions for ERC-8001
 */

import type { Hex } from './types';

// ═══════════════════════════════════════════════════════════════════════════
// TYPE HASHES (computed from Solidity type strings)
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Compute the keccak256 hash of the AgentIntent type string.
 * "AgentIntent(bytes32 payloadHash,uint64 expiry,uint64 nonce,address agentId,bytes32 coordinationType,uint256 coordinationValue,address[] participants)"
 */
function computeAgentIntentTypehash(): Hex {
  const typeString = "AgentIntent(bytes32 payloadHash,uint64 expiry,uint64 nonce,address agentId,bytes32 coordinationType,uint256 coordinationValue,address[] participants)";
  // This would normally be computed with keccak256
  return `0x${Buffer.from(typeString).toString('hex')}` as Hex; // Placeholder - actual computation needed
}

/**
 * Compute the keccak256 hash of the AcceptanceAttestation type string.
 * "AcceptanceAttestation(bytes32 intentHash,address participant,uint64 nonce,uint64 expiry,bytes32 conditionsHash)"
 * Note: signature field is NOT included in the typehash (not signed over)
 */
function computeAcceptanceTypehash(): Hex {
  const typeString = "AcceptanceAttestation(bytes32 intentHash,address participant,uint64 nonce,uint64 expiry,bytes32 conditionsHash)";
  return `0x${Buffer.from(typeString).toString('hex')}` as Hex; // Placeholder
}

// Actual computed typehashes (you should compute these properly)
export const AGENT_INTENT_TYPEHASH: Hex =
  '0x0000000000000000000000000000000000000000000000000000000000000000' as Hex; // TODO: compute actual hash

export const ACCEPTANCE_TYPEHASH: Hex =
  '0x0000000000000000000000000000000000000000000000000000000000000000' as Hex; // TODO: compute actual hash

export const BOUNDED_INTENT_TYPEHASH: Hex =
  '0x0000000000000000000000000000000000000000000000000000000000000000' as Hex; // TODO: compute actual hash

// ═══════════════════════════════════════════════════════════════════════════
// EIP-712 TYPE DEFINITIONS
// ═══════════════════════════════════════════════════════════════════════════

/**
 * EIP-712 types for AgentIntent
 * Matches: AgentIntent(bytes32 payloadHash,uint64 expiry,uint64 nonce,address agentId,bytes32 coordinationType,uint256 coordinationValue,address[] participants)
 */
export const AGENT_INTENT_TYPES = {
  AgentIntent: [
    { name: 'payloadHash', type: 'bytes32' },
    { name: 'expiry', type: 'uint64' },
    { name: 'nonce', type: 'uint64' },
    { name: 'agentId', type: 'address' },
    { name: 'coordinationType', type: 'bytes32' },
    { name: 'coordinationValue', type: 'uint256' },
    { name: 'participants', type: 'address[]' },
  ],
} as const;

/**
 * EIP-712 types for AcceptanceAttestation
 * Note: signature field is NOT part of the signed data (it's the signature itself)
 * Matches: AcceptanceAttestation(bytes32 intentHash,address participant,uint64 nonce,uint64 expiry,bytes32 conditionsHash)
 */
export const ACCEPTANCE_TYPES = {
  AcceptanceAttestation: [
    { name: 'intentHash', type: 'bytes32' },
    { name: 'participant', type: 'address' },
    { name: 'nonce', type: 'uint64' },
    { name: 'expiry', type: 'uint64' },
    { name: 'conditionsHash', type: 'bytes32' },
  ],
} as const;

/**
 * EIP-712 types for BoundedIntent
 */
export const BOUNDED_INTENT_TYPES = {
  BoundedIntent: [
    { name: 'payloadHash', type: 'bytes32' },
    { name: 'expiry', type: 'uint64' },
    { name: 'nonce', type: 'uint64' },
    { name: 'agentId', type: 'address' },
    { name: 'policyEpoch', type: 'uint256' },
  ],
} as const;

// ═══════════════════════════════════════════════════════════════════════════
// DOMAIN BUILDERS
// ═══════════════════════════════════════════════════════════════════════════

export interface DomainParams {
  name: string;
  version: string;
  chainId: bigint | number;
  verifyingContract: `0x${string}`;
}

/**
 * Build EIP-712 domain for ERC-8001 coordinator
 * Per spec: {name: "ERC-8001", version: "1", chainId, verifyingContract}
 */
export function buildERC8001Domain(params: {
  chainId: bigint | number;
  verifyingContract: `0x${string}`;
}) {
  return {
    name: 'ERC-8001',
    version: '1',
    chainId: BigInt(params.chainId),
    verifyingContract: params.verifyingContract,
  };
}

/**
 * Default domain for BoundedAgentExecutor
 */
export function buildBoundedExecutorDomain(
  chainId: bigint | number,
  verifyingContract: `0x${string}`
) {
  return {
    name: 'BoundedAgentExecutor',
    version: '1',
    chainId: BigInt(chainId),
    verifyingContract,
  };
}
