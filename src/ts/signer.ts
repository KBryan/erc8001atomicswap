/**
 * ERC-8001 Signer
 * High-level API for signing intents and attestations
 */

import type { Address, Hex } from './types';
import type {
  AgentIntent,
  AcceptanceAttestation,
  BoundedIntent,
  CoordinationPayload,
  BoundedPayload,
} from './types';
import {
  AGENT_INTENT_TYPES,
  ACCEPTANCE_TYPES,
  BOUNDED_INTENT_TYPES,
  type DomainParams,
} from './eip712';
import {
  hashAgentIntent,
  hashAcceptanceAttestation,
  hashBoundedIntent,
  createAgentIntent,
  createBoundedIntent,
  createAcceptance,
  type CreateIntentParams,
  type CreateBoundedIntentParams,
} from './utils';

// ═══════════════════════════════════════════════════════════════════════════
// ABSTRACT SIGNER
// ═══════════════════════════════════════════════════════════════════════════

export interface SignTypedDataParams {
  domain: DomainParams;
  types: Record<string, { name: string; type: string }[]>;
  primaryType: string;
  message: Record<string, unknown>;
}

/**
 * Abstract signer interface - implement for your wallet/signer
 */
export interface TypedDataSigner {
  getAddress(): Promise<Address>;
  signTypedData(params: SignTypedDataParams): Promise<Hex>;
}

// ═══════════════════════════════════════════════════════════════════════════
// ERC-8001 SIGNER
// ═══════════════════════════════════════════════════════════════════════════

export class ERC8001Signer {
  constructor(
    private readonly signer: TypedDataSigner,
    private readonly domain: DomainParams
  ) {}

  /**
   * Create and sign an AgentIntent
   */
  async signIntent(
    params: Omit<CreateIntentParams, 'agentId'>
  ): Promise<{ intent: AgentIntent; payload: CoordinationPayload; signature: Hex }> {
    const agentId = await this.signer.getAddress();
    const { intent, payload } = createAgentIntent({ ...params, agentId });

    const signature = await this.signer.signTypedData({
      domain: this.domain,
      types: AGENT_INTENT_TYPES,
      primaryType: 'AgentIntent',
      message: {
        payloadHash: intent.payloadHash,
        expiry: intent.expiry,
        nonce: intent.nonce,
        agentId: intent.agentId,
        coordinationType: intent.coordinationType,
        coordinationValue: intent.coordinationValue,
        participants: intent.participants,
      },
    });

    return { intent, payload, signature };
  }

  /**
   * Sign an acceptance attestation
   */
  async signAcceptance(
    intentHash: Hex,
    expirySeconds?: number
  ): Promise<{ attestation: AcceptanceAttestation; signature: Hex }> {
    const agentId = await this.signer.getAddress();
    const attestation = createAcceptance(intentHash, agentId, expirySeconds);

    const signature = await this.signer.signTypedData({
      domain: this.domain,
      types: ACCEPTANCE_TYPES,
      primaryType: 'AcceptanceAttestation',
      message: {
        intentHash: attestation.intentHash,
        expiry: attestation.expiry,
        agentId: attestation.agentId,
      },
    });

    return { attestation, signature };
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// BOUNDED EXECUTOR SIGNER
// ═══════════════════════════════════════════════════════════════════════════

export class BoundedExecutorSigner {
  constructor(
    private readonly signer: TypedDataSigner,
    private readonly domain: DomainParams
  ) {}

  /**
   * Create and sign a BoundedIntent
   */
  async signIntent(
    params: Omit<CreateBoundedIntentParams, 'agentId'>
  ): Promise<{ intent: BoundedIntent; payload: BoundedPayload; signature: Hex }> {
    const agentId = await this.signer.getAddress();
    const { intent, payload } = createBoundedIntent({ ...params, agentId });

    const signature = await this.signer.signTypedData({
      domain: this.domain,
      types: BOUNDED_INTENT_TYPES,
      primaryType: 'BoundedIntent',
      message: {
        payloadHash: intent.payloadHash,
        expiry: intent.expiry,
        nonce: intent.nonce,
        agentId: intent.agentId,
        policyEpoch: intent.policyEpoch,
      },
    });

    return { intent, payload, signature };
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// VIEM ADAPTER
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Create a TypedDataSigner from a viem WalletClient
 */
export function fromViemWallet(walletClient: {
  account: { address: Address };
  signTypedData: (params: {
    domain: {
      name: string;
      version: string;
      chainId: bigint | number;
      verifyingContract: Address;
    };
    types: Record<string, { name: string; type: string }[]>;
    primaryType: string;
    message: Record<string, unknown>;
  }) => Promise<Hex>;
}): TypedDataSigner {
  return {
    getAddress: async () => walletClient.account.address,
    signTypedData: async (params) =>
      walletClient.signTypedData({
        domain: {
          name: params.domain.name,
          version: params.domain.version,
          chainId: params.domain.chainId,
          verifyingContract: params.domain.verifyingContract,
        },
        types: params.types,
        primaryType: params.primaryType,
        message: params.message,
      }),
  };
}

// ═══════════════════════════════════════════════════════════════════════════
// ETHERS ADAPTER
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Create a TypedDataSigner from an ethers Signer
 */
export function fromEthersSigner(signer: {
  getAddress: () => Promise<string>;
  signTypedData: (
    domain: {
      name: string;
      version: string;
      chainId: bigint | number;
      verifyingContract: string;
    },
    types: Record<string, { name: string; type: string }[]>,
    value: Record<string, unknown>
  ) => Promise<string>;
}): TypedDataSigner {
  return {
    getAddress: async () => (await signer.getAddress()) as Address,
    signTypedData: async (params) =>
      (await signer.signTypedData(
        {
          name: params.domain.name,
          version: params.domain.version,
          chainId: params.domain.chainId,
          verifyingContract: params.domain.verifyingContract,
        },
        params.types,
        params.message
      )) as Hex,
  };
}
