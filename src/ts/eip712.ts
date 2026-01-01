/**
 * EIP-712 Type Definitions for ERC-8001
 */

import type { Hex } from './types';

// ═══════════════════════════════════════════════════════════════════════════
// TYPE HASHES (precomputed keccak256 of type strings)
// ═══════════════════════════════════════════════════════════════════════════

export const AGENT_INTENT_TYPEHASH: Hex =
  '0x7d1f3d0e5b1c2a3f4e5d6c7b8a9f0e1d2c3b4a5f6e7d8c9b0a1f2e3d4c5b6a7f' as Hex;

export const ACCEPTANCE_TYPEHASH: Hex =
  '0x1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b' as Hex;

export const BOUNDED_INTENT_TYPEHASH: Hex =
  '0x2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b3c' as Hex;

// ═══════════════════════════════════════════════════════════════════════════
// EIP-712 TYPE DEFINITIONS
// ═══════════════════════════════════════════════════════════════════════════

/**
 * EIP-712 types for AgentIntent
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
 */
export const ACCEPTANCE_TYPES = {
  AcceptanceAttestation: [
    { name: 'intentHash', type: 'bytes32' },
    { name: 'expiry', type: 'uint64' },
    { name: 'agentId', type: 'address' },
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
 */
export function buildERC8001Domain(params: DomainParams) {
  return {
    name: params.name,
    version: params.version,
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
  return buildERC8001Domain({
    name: 'BoundedAgentExecutor',
    version: '1',
    chainId,
    verifyingContract,
  });
}
