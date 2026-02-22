/**
 * Viem-based signing utilities for ERC-8001
 */

import {
  type Address,
  type Hex,
  encodeAbiParameters,
  keccak256,
  encodePacked,
} from 'viem';
import type {
  AgentIntent,
  AcceptanceAttestation,
  BoundedIntent,
  BoundedPayload,
  CoordinationPayload,
} from './types';

// ═══════════════════════════════════════════════════════════════════════════
// HASH FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Hash a CoordinationPayload
 * Per spec: keccak256(abi.encode(version, coordinationType, keccak256(coordinationData), conditionsHash, timestamp, keccak256(metadata)))
 */
export function hashCoordinationPayload(payload: CoordinationPayload): Hex {
  return keccak256(
    encodeAbiParameters(
      [
        { type: 'bytes32' },
        { type: 'bytes32' },
        { type: 'bytes32' },
        { type: 'bytes32' },
        { type: 'uint256' },
        { type: 'bytes32' },
      ],
      [
        payload.version,
        payload.coordinationType,
        keccak256(payload.coordinationData),
        payload.conditionsHash,
        payload.timestamp,
        keccak256(payload.metadata),
      ]
    )
  );
}

/**
 * Hash a BoundedPayload
 */
export function hashBoundedPayload(payload: BoundedPayload): Hex {
  return keccak256(
    encodeAbiParameters(
      [
        { type: 'bytes32' },
        { type: 'address' },
        { type: 'address' },
        { type: 'uint256' },
        { type: 'bytes32' },
      ],
      [
        payload.policyRoot,
        payload.target,
        payload.asset,
        payload.amount,
        payload.calldataHash,
      ]
    )
  );
}

/**
 * Hash an AgentIntent (for EIP-712 struct hash)
 * Per spec: keccak256(abi.encode(AGENT_INTENT_TYPEHASH, payloadHash, expiry, nonce, agentId, coordinationType, coordinationValue, keccak256(abi.encodePacked(participants))))
 */
export function hashAgentIntent(intent: AgentIntent, typehash: Hex): Hex {
  return keccak256(
    encodeAbiParameters(
      [
        { type: 'bytes32' },
        { type: 'bytes32' },
        { type: 'uint64' },
        { type: 'uint64' },
        { type: 'address' },
        { type: 'bytes32' },
        { type: 'uint256' },
        { type: 'bytes32' },
      ],
      [
        typehash,
        intent.payloadHash,
        intent.expiry,
        intent.nonce,
        intent.agentId,
        intent.coordinationType,
        intent.coordinationValue,
        keccak256(encodePacked(['address[]'], [intent.participants])),
      ]
    )
  );
}

/**
 * Hash an AcceptanceAttestation (for EIP-712 struct hash)
 * Per spec: keccak256(abi.encode(ACCEPTANCE_TYPEHASH, intentHash, participant, nonce, expiry, conditionsHash))
 * Note: signature field is NOT part of the hash
 */
export function hashAcceptanceAttestation(
  attestation: Omit<AcceptanceAttestation, 'signature'>,
  typehash: Hex
): Hex {
  return keccak256(
    encodeAbiParameters(
      [
        { type: 'bytes32' },
        { type: 'bytes32' },
        { type: 'address' },
        { type: 'uint64' },
        { type: 'uint64' },
        { type: 'bytes32' },
      ],
      [
        typehash,
        attestation.intentHash,
        attestation.participant,
        attestation.nonce,
        attestation.expiry,
        attestation.conditionsHash,
      ]
    )
  );
}

/**
 * Hash a BoundedIntent
 */
export function hashBoundedIntent(
  intent: BoundedIntent,
  typehash: Hex
): Hex {
  return keccak256(
    encodeAbiParameters(
      [
        { type: 'bytes32' },
        { type: 'bytes32' },
        { type: 'uint64' },
        { type: 'uint64' },
        { type: 'address' },
        { type: 'uint256' },
      ],
      [
        typehash,
        intent.payloadHash,
        intent.expiry,
        intent.nonce,
        intent.agentId,
        intent.policyEpoch,
      ]
    )
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// POLICY LEAF HASH
// ═══════════════════════════════════════════════════════════════════════════

const POLICY_LEAF_DOMAIN = keccak256(
  encodePacked(['string'], ['POLICY_LEAF_V1'])
);

/**
 * Compute policy leaf for Merkle tree
 */
export function computePolicyLeaf(
  target: Address,
  asset: Address,
  amount: bigint
): Hex {
  return keccak256(
    encodeAbiParameters(
      [
        { type: 'bytes32' },
        { type: 'address' },
        { type: 'address' },
        { type: 'uint256' },
      ],
      [POLICY_LEAF_DOMAIN, target, asset, amount]
    )
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// INTENT BUILDERS
// ═══════════════════════════════════════════════════════════════════════════

export interface CreateIntentParams {
  agentId: Address;
  coordinationType: Hex;
  coordinationValue?: bigint;
  participants: Address[];
  coordinationData: Hex;
  nonce: bigint;
  expirySeconds?: number;
  version?: Hex;
  conditionsHash?: Hex;
  timestamp?: bigint;
  metadata?: Hex;
}

/**
 * Create an AgentIntent with computed payload hash
 * Per spec: participants MUST be sorted ascending by uint160(address)
 */
export function createAgentIntent(
  params: CreateIntentParams
): { intent: AgentIntent; payload: CoordinationPayload } {
  const version = params.version ?? keccak256(encodePacked(['string'], ['V1']));
  const expiry = BigInt(
    Math.floor(Date.now() / 1000) + (params.expirySeconds ?? 3600)
  );
  const conditionsHash = params.conditionsHash ?? ('0x0000000000000000000000000000000000000000000000000000000000000000' as Hex);
  const timestamp = params.timestamp ?? BigInt(Math.floor(Date.now() / 1000));
  const metadata = params.metadata ?? ('0x' as Hex);

  // Validate participants are sorted ascending (per spec requirement)
  const sortedParticipants = [...params.participants].sort((a, b) => {
    return BigInt(a) < BigInt(b) ? -1 : 1;
  });

  const payload: CoordinationPayload = {
    version,
    coordinationType: params.coordinationType,
    coordinationData: params.coordinationData,
    conditionsHash,
    timestamp,
    metadata,
  };

  const payloadHash = hashCoordinationPayload(payload);

  const intent: AgentIntent = {
    payloadHash,
    expiry,
    nonce: params.nonce,
    agentId: params.agentId,
    coordinationType: params.coordinationType,
    coordinationValue: params.coordinationValue ?? 0n,
    participants: sortedParticipants,
  };

  return { intent, payload };
}

export interface CreateBoundedIntentParams {
  agentId: Address;
  policyRoot: Hex;
  policyEpoch: bigint;
  target: Address;
  asset: Address;
  amount: bigint;
  calldataHash?: Hex;
  nonce: bigint;
  expirySeconds?: number;
}

/**
 * Create a BoundedIntent with computed payload hash
 */
export function createBoundedIntent(
  params: CreateBoundedIntentParams
): { intent: BoundedIntent; payload: BoundedPayload } {
  const expiry = BigInt(
    Math.floor(Date.now() / 1000) + (params.expirySeconds ?? 3600)
  );

  const payload: BoundedPayload = {
    policyRoot: params.policyRoot,
    target: params.target,
    asset: params.asset,
    amount: params.amount,
    calldataHash:
      params.calldataHash ??
      ('0x0000000000000000000000000000000000000000000000000000000000000000' as Hex),
  };

  const payloadHash = hashBoundedPayload(payload);

  const intent: BoundedIntent = {
    payloadHash,
    expiry,
    nonce: params.nonce,
    agentId: params.agentId,
    policyEpoch: params.policyEpoch,
  };

  return { intent, payload };
}

/**
 * Create an AcceptanceAttestation
 * Per spec: includes signature field (excluded from hash)
 */
export function createAcceptance(
  intentHash: Hex,
  participant: Address,
  nonce: bigint,
  expirySeconds?: number,
  conditionsHash?: Hex,
  signature?: Hex
): AcceptanceAttestation {
  const expiry = BigInt(
    Math.floor(Date.now() / 1000) + (expirySeconds ?? 3600)
  );

  return {
    intentHash,
    participant,
    nonce,
    expiry,
    conditionsHash: conditionsHash ?? ('0x0000000000000000000000000000000000000000000000000000000000000000' as Hex),
    signature: signature ?? ('0x' as Hex),
  };
}

// ═══════════════════════════════════════════════════════════════════════════
// HELPER FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Validate that participants are in strictly ascending order (per ERC-8001 spec)
 */
export function validateParticipantsCanonical(participants: Address[]): boolean {
  if (participants.length === 0) return false;
  
  for (let i = 1; i < participants.length; i++) {
    if (BigInt(participants[i]) <= BigInt(participants[i - 1])) {
      return false;
    }
  }
  return true;
}

/**
 * Sort participants in ascending order
 */
export function sortParticipants(participants: Address[]): Address[] {
  return [...participants].sort((a, b) => {
    return BigInt(a) < BigInt(b) ? -1 : 1;
  });
}
