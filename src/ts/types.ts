/**
 * ERC-8001 Type Definitions
 * Matches the Solidity struct definitions in IERC8001.sol
 */

// ═══════════════════════════════════════════════════════════════════════════
// ENUMS
// ═══════════════════════════════════════════════════════════════════════════

export enum CoordinationStatus {
  None = 0,
  Proposed = 1,
  Ready = 2,
  Executed = 3,
  Cancelled = 4,
}

// ═══════════════════════════════════════════════════════════════════════════
// ERC-8001 STRUCTS
// ═══════════════════════════════════════════════════════════════════════════

/**
 * The core intent structure signed by the proposer.
 */
export interface AgentIntent {
  payloadHash: `0x${string}`;
  expiry: bigint;
  nonce: bigint;
  agentId: `0x${string}`;
  coordinationType: `0x${string}`;
  coordinationValue: bigint;
  participants: `0x${string}`[];
}

/**
 * Acceptance attestation signed by each participant.
 */
export interface AcceptanceAttestation {
  intentHash: `0x${string}`;
  expiry: bigint;
  agentId: `0x${string}`;
}

/**
 * Application-specific coordination payload.
 */
export interface CoordinationPayload {
  version: `0x${string}`;
  coordinationType: `0x${string}`;
  participants: `0x${string}`[];
  coordinationData: `0x${string}`;
}

// ═══════════════════════════════════════════════════════════════════════════
// BOUNDED AGENT EXECUTOR STRUCTS
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Intent for bounded execution.
 */
export interface BoundedIntent {
  payloadHash: `0x${string}`;
  expiry: bigint;
  nonce: bigint;
  agentId: `0x${string}`;
  policyEpoch: bigint;
}

/**
 * Payload for bounded operations.
 */
export interface BoundedPayload {
  policyRoot: `0x${string}`;
  target: `0x${string}`;
  asset: `0x${string}`;
  amount: bigint;
  calldataHash: `0x${string}`;
}

/**
 * Agent budget configuration.
 */
export interface AgentBudget {
  dailyLimit: bigint;
  spentToday: bigint;
  periodStart: bigint;
}

// ═══════════════════════════════════════════════════════════════════════════
// HELPER TYPES
// ═══════════════════════════════════════════════════════════════════════════

export type Hex = `0x${string}`;
export type Address = `0x${string}`;

/**
 * EIP-712 Domain
 */
export interface EIP712Domain {
  name: string;
  version: string;
  chainId: bigint;
  verifyingContract: Address;
}

/**
 * Signed intent ready for submission
 */
export interface SignedIntent<T> {
  intent: T;
  signature: Hex;
}
