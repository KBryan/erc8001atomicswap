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
import {
  AGENT_INTENT_TYPES,
  ACCEPTANCE_TYPES,
  BOUNDED_INTENT_TYPES,
  type DomainParams,
} from './eip712';

// ═══════════════════════════════════════════════════════════════════════════
// HASH FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Hash a CoordinationPayload
 */
export function hashCoordinationPayload(payload: CoordinationPayload): Hex {
  return keccak256(
    encodeAbiParameters(
      [
        { type: 'bytes32' },
        { type: 'bytes32' },
        { type: 'bytes32' },
        { type: 'bytes32' },
      ],
      [
        payload.version,
        payload.coordinationType,
        keccak256(encodePacked(['address[]'], [payload.participants])),
        keccak256(payload.coordinationData),
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
 */
export function hashAgentIntent(intent: AgentIntent): Hex {
  const typeHash = keccak256(
    encodePacked(
      ['string'],
      [
        'AgentIntent(bytes32 payloadHash,uint64 expiry,uint64 nonce,address agentId,bytes32 coordinationType,uint256 coordinationValue,address[] participants)',
      ]
    )
  );

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
        typeHash,
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
 * Hash an AcceptanceAttestation
 */
export function hashAcceptanceAttestation(
  attestation: AcceptanceAttestation
): Hex {
  const typeHash = keccak256(
    encodePacked(
      ['string'],
      ['AcceptanceAttestation(bytes32 intentHash,uint64 expiry,address agentId)']
    )
  );

  return keccak256(
    encodeAbiParameters(
      [
        { type: 'bytes32' },
        { type: 'bytes32' },
        { type: 'uint64' },
        { type: 'address' },
      ],
      [typeHash, attestation.intentHash, attestation.expiry, attestation.agentId]
    )
  );
}

/**
 * Hash a BoundedIntent
 */
export function hashBoundedIntent(intent: BoundedIntent): Hex {
  const typeHash = keccak256(
    encodePacked(
      ['string'],
      [
        'BoundedIntent(bytes32 payloadHash,uint64 expiry,uint64 nonce,address agentId,uint256 policyEpoch)',
      ]
    )
  );

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
        typeHash,
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
}

/**
 * Create an AgentIntent with computed payload hash
 */
export function createAgentIntent(
  params: CreateIntentParams
): { intent: AgentIntent; payload: CoordinationPayload } {
  const version =
    params.version ?? keccak256(encodePacked(['string'], ['V1']));
  const expiry = BigInt(
    Math.floor(Date.now() / 1000) + (params.expirySeconds ?? 3600)
  );

  const payload: CoordinationPayload = {
    version,
    coordinationType: params.coordinationType,
    participants: params.participants,
    coordinationData: params.coordinationData,
  };

  const payloadHash = hashCoordinationPayload(payload);

  const intent: AgentIntent = {
    payloadHash,
    expiry,
    nonce: params.nonce,
    agentId: params.agentId,
    coordinationType: params.coordinationType,
    coordinationValue: params.coordinationValue ?? 0n,
    participants: params.participants,
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
 */
export function createAcceptance(
  intentHash: Hex,
  agentId: Address,
  expirySeconds?: number
): AcceptanceAttestation {
  const expiry = BigInt(
    Math.floor(Date.now() / 1000) + (expirySeconds ?? 3600)
  );

  return {
    intentHash,
    expiry,
    agentId,
  };
}
