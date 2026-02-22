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
  Expired = 5,
}

// ═══════════════════════════════════════════════════════════════════════════
// ERC-8001 STRUCTS
// ═══════════════════════════════════════════════════════════════════════════

/**
 * The core intent structure signed by the proposer.
 * @param payloadHash       keccak256(CoordinationPayload)
 * @param expiry            Unix timestamp after which the intent is invalid
 * @param nonce             Per-agent monotonic nonce for replay protection
 * @param agentId           Address of the proposing agent
 * @param coordinationType  Domain-specific type identifier
 * @param coordinationValue Optional value associated with coordination
 * @param participants      Required participants who must accept (sorted ascending)
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
 * @param intentHash     Hash of the intent being accepted (struct hash, not digest)
 * @param participant    Address of the accepting agent
 * @param nonce          Per-acceptance monotonic nonce (optional in Core)
 * @param expiry         Unix timestamp after which the acceptance is invalid
 * @param conditionsHash Participant constraints
 * @param signature      ECDSA (65 or 64 bytes) or ERC-1271 signature
 */
export interface AcceptanceAttestation {
  intentHash: `0x${string}`;
  participant: `0x${string}`;
  nonce: bigint;
  expiry: bigint;
  conditionsHash: `0x${string}`;
  signature: `0x${string}`;
}

/**
 * Application-specific coordination payload.
 * @param version          Payload format version
 * @param coordinationType Type identifier matching AgentIntent
 * @param coordinationData Application-specific encoded data
 * @param conditionsHash   Domain-specific conditions hash
 * @param timestamp        Creation time (informational)
 * @param metadata         Optional additional data
 */
export interface CoordinationPayload {
  version: `0x${string}`;
  coordinationType: `0x${string}`;
  coordinationData: `0x${string}`;
  conditionsHash: `0x${string}`;
  timestamp: bigint;
  metadata: `0x${string}`;
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

/**
 * Coordination status with full details
 */
export interface CoordinationStatusFull {
  status: CoordinationStatus;
  proposer: Address;
  participants: Address[];
  acceptedBy: Address[];
  expiry: bigint;
}
