/**
 * ERC-8001 SDK
 * Agent Coordination Framework
 */

// Types
export type {
  AgentIntent,
  AcceptanceAttestation,
  CoordinationPayload,
  BoundedIntent,
  BoundedPayload,
  AgentBudget,
  EIP712Domain,
  SignedIntent,
  Hex,
  Address,
} from './types';

export { CoordinationStatus } from './types';

// EIP-712
export {
  AGENT_INTENT_TYPES,
  ACCEPTANCE_TYPES,
  BOUNDED_INTENT_TYPES,
  buildERC8001Domain,
  buildBoundedExecutorDomain,
  type DomainParams,
} from './eip712';

// Utilities
export {
  hashCoordinationPayload,
  hashBoundedPayload,
  hashAgentIntent,
  hashAcceptanceAttestation,
  hashBoundedIntent,
  computePolicyLeaf,
  createAgentIntent,
  createBoundedIntent,
  createAcceptance,
  type CreateIntentParams,
  type CreateBoundedIntentParams,
} from './utils';

// Signers
export {
  ERC8001Signer,
  BoundedExecutorSigner,
  fromViemWallet,
  fromEthersSigner,
  type TypedDataSigner,
  type SignTypedDataParams,
} from './signer';
