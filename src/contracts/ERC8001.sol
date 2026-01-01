// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC8001} from "./interfaces/IERC8001.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

/**
 * @title ERC8001
 * @dev Base implementation of ERC-8001 Agent Coordination Framework.
 *
 * This contract provides the core coordination primitives:
 * - Propose: Initiator posts a signed intent with required participants
 * - Accept: Each participant signs an acceptance attestation
 * - Execute: Once all participants accept, anyone can trigger execution
 *
 * Execution logic is left to inheriting contracts via the `_executeCoordination` hook.
 *
 * See https://eips.ethereum.org/EIPS/eip-8001
 */
abstract contract ERC8001 is IERC8001, EIP712 {
    using ECDSA for bytes32;

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev EIP-712 typehash for AgentIntent
    bytes32 public constant AGENT_INTENT_TYPEHASH = keccak256(
        "AgentIntent(bytes32 payloadHash,uint64 expiry,uint64 nonce,address agentId,bytes32 coordinationType,uint256 coordinationValue,address[] participants)"
    );

    /// @dev EIP-712 typehash for AcceptanceAttestation
    bytes32 public constant ACCEPTANCE_TYPEHASH = keccak256(
        "AcceptanceAttestation(bytes32 intentHash,uint64 expiry,address agentId)"
    );

    /// @dev EIP-1271 magic value for valid signatures
    bytes4 private constant EIP1271_MAGIC = 0x1626ba7e;

    // ═══════════════════════════════════════════════════════════════════════════
    // STORAGE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Coordination state by intent hash
    struct CoordinationState {
        Status status;
        bytes32 payloadHash;
        address proposer;
        uint64 expiry;
        address[] participants;
        mapping(address => bool) accepted;
        uint256 acceptedCount;
    }

    /// @dev Intent hash => coordination state
    mapping(bytes32 => CoordinationState) internal _coordinations;

    /// @dev Agent address => current nonce
    mapping(address => uint64) internal _agentNonces;

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @dev Initializes the EIP-712 domain.
     * @param name The protocol name for EIP-712 domain
     * @param version The protocol version for EIP-712 domain
     */
    constructor(
        string memory name,
        string memory version
    ) EIP712(name, version) {}

    // ═══════════════════════════════════════════════════════════════════════════
    // EXTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc IERC8001
    function proposeCoordination(
        AgentIntent calldata intent,
        CoordinationPayload calldata payload,
        bytes calldata signature
    ) external virtual returns (bytes32 intentHash) {
        // Validate expiry
        if (intent.expiry <= block.timestamp) {
            revert IntentExpired(intent.expiry, uint64(block.timestamp));
        }

        // Validate nonce
        uint64 currentNonce = _agentNonces[intent.agentId];
        if (intent.nonce <= currentNonce) {
            revert NonceTooLow(intent.nonce, currentNonce + 1);
        }

        // Compute intent hash
        intentHash = _hashIntent(intent);

        // Check intent doesn't already exist
        if (_coordinations[intentHash].status != Status.None) {
            revert IntentAlreadyExists(intentHash);
        }

        // Verify payload hash matches
        bytes32 computedPayloadHash = _hashPayload(payload);
        if (intent.payloadHash != computedPayloadHash) {
            revert PayloadMismatch(intent.payloadHash, computedPayloadHash);
        }

        // Verify signature
        bytes32 digest = _hashTypedDataV4(intentHash);
        if (!_verifySignature(intent.agentId, digest, signature)) {
            revert InvalidSignature(intent.agentId, address(0));
        }

        // Update nonce
        _agentNonces[intent.agentId] = intent.nonce;

        // Store coordination
        CoordinationState storage coord = _coordinations[intentHash];
        coord.status = Status.Proposed;
        coord.payloadHash = intent.payloadHash;
        coord.proposer = intent.agentId;
        coord.expiry = intent.expiry;
        coord.participants = intent.participants;

        // Proposer auto-accepts if they're a participant
        for (uint256 i = 0; i < intent.participants.length; i++) {
            if (intent.participants[i] == intent.agentId) {
                coord.accepted[intent.agentId] = true;
                coord.acceptedCount = 1;
                break;
            }
        }

        emit CoordinationProposed(
            intentHash,
            intent.agentId,
            intent.coordinationType,
            intent.participants,
            intent.expiry
        );

        // Check if ready (single participant case)
        if (coord.acceptedCount == coord.participants.length) {
            coord.status = Status.Ready;
            emit CoordinationReady(intentHash);
        }

        return intentHash;
    }

    /// @inheritdoc IERC8001
    function acceptCoordination(
        bytes32 intentHash,
        AcceptanceAttestation calldata attestation,
        bytes calldata signature
    ) external virtual {
        CoordinationState storage coord = _coordinations[intentHash];

        // Validate coordination exists and is proposed
        if (coord.status == Status.None) {
            revert IntentNotFound(intentHash);
        }
        if (coord.status != Status.Proposed) {
            revert NotReady(intentHash, coord.status);
        }

        // Validate acceptance attestation
        if (attestation.intentHash != intentHash) {
            revert PayloadMismatch(intentHash, attestation.intentHash);
        }
        if (attestation.expiry <= block.timestamp) {
            revert AcceptanceExpired(attestation.expiry, uint64(block.timestamp));
        }

        // Check participant is required
        bool isParticipant = false;
        for (uint256 i = 0; i < coord.participants.length; i++) {
            if (coord.participants[i] == attestation.agentId) {
                isParticipant = true;
                break;
            }
        }
        if (!isParticipant) {
            revert NotParticipant(intentHash, attestation.agentId);
        }

        // Check not already accepted
        if (coord.accepted[attestation.agentId]) {
            revert AlreadyAccepted(intentHash, attestation.agentId);
        }

        // Verify signature
        bytes32 attestationHash = _hashAttestation(attestation);
        bytes32 digest = _hashTypedDataV4(attestationHash);
        if (!_verifySignature(attestation.agentId, digest, signature)) {
            revert InvalidSignature(attestation.agentId, address(0));
        }

        // Record acceptance
        coord.accepted[attestation.agentId] = true;
        coord.acceptedCount++;

        emit CoordinationAccepted(
            intentHash,
            attestation.agentId,
            coord.acceptedCount,
            coord.participants.length
        );

        // Check if all participants have accepted
        if (coord.acceptedCount == coord.participants.length) {
            coord.status = Status.Ready;
            emit CoordinationReady(intentHash);
        }
    }

    /// @inheritdoc IERC8001
    function executeCoordination(
        bytes32 intentHash,
        CoordinationPayload calldata payload,
        bytes calldata executionData
    ) external virtual {
        CoordinationState storage coord = _coordinations[intentHash];

        // Validate status
        if (coord.status != Status.Ready) {
            revert NotReady(intentHash, coord.status);
        }

        // Validate not expired
        if (coord.expiry <= block.timestamp) {
            revert IntentExpired(coord.expiry, uint64(block.timestamp));
        }

        // Verify payload matches
        bytes32 computedPayloadHash = _hashPayload(payload);
        if (coord.payloadHash != computedPayloadHash) {
            revert PayloadMismatch(coord.payloadHash, computedPayloadHash);
        }

        // Update status before execution (reentrancy protection)
        coord.status = Status.Executed;

        // Execute application-specific logic
        _executeCoordination(intentHash, payload, executionData);

        emit CoordinationExecuted(intentHash, msg.sender);
    }

    /// @inheritdoc IERC8001
    function cancelCoordination(bytes32 intentHash) external virtual {
        CoordinationState storage coord = _coordinations[intentHash];

        if (coord.status == Status.None) {
            revert IntentNotFound(intentHash);
        }
        if (coord.status == Status.Executed || coord.status == Status.Cancelled) {
            revert NotReady(intentHash, coord.status);
        }
        if (msg.sender != coord.proposer) {
            revert NotAuthorizedToCancel(intentHash, msg.sender);
        }

        coord.status = Status.Cancelled;

        emit CoordinationCancelled(intentHash, msg.sender);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc IERC8001
    function getCoordinationStatus(
        bytes32 intentHash
    ) external view virtual returns (Status) {
        return _coordinations[intentHash].status;
    }

    /// @inheritdoc IERC8001
    function getCoordination(
        bytes32 intentHash
    ) external view virtual returns (
        Status status,
        bytes32 payloadHash,
        address[] memory participants,
        address[] memory accepted,
        uint64 expiry
    ) {
        CoordinationState storage coord = _coordinations[intentHash];
        
        status = coord.status;
        payloadHash = coord.payloadHash;
        participants = coord.participants;
        expiry = coord.expiry;

        // Build accepted array
        uint256 count = coord.acceptedCount;
        accepted = new address[](count);
        uint256 idx = 0;
        for (uint256 i = 0; i < coord.participants.length && idx < count; i++) {
            if (coord.accepted[coord.participants[i]]) {
                accepted[idx++] = coord.participants[i];
            }
        }
    }

    /// @inheritdoc IERC8001
    function getAgentNonce(address agentId) external view virtual returns (uint64) {
        return _agentNonces[agentId];
    }

    /// @inheritdoc IERC8001
    function hasAccepted(
        bytes32 intentHash,
        address participant
    ) external view virtual returns (bool) {
        return _coordinations[intentHash].accepted[participant];
    }

    /// @inheritdoc IERC8001
    function DOMAIN_SEPARATOR() external view virtual returns (bytes32) {
        return _domainSeparatorV4();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @dev Hook for application-specific execution logic.
     *      MUST be implemented by inheriting contracts.
     * @param intentHash The coordination being executed
     * @param payload The coordination payload
     * @param executionData Optional execution-specific data
     */
    function _executeCoordination(
        bytes32 intentHash,
        CoordinationPayload calldata payload,
        bytes calldata executionData
    ) internal virtual;

    /**
     * @dev Compute the EIP-712 struct hash for an AgentIntent.
     */
    function _hashIntent(AgentIntent calldata intent) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            AGENT_INTENT_TYPEHASH,
            intent.payloadHash,
            intent.expiry,
            intent.nonce,
            intent.agentId,
            intent.coordinationType,
            intent.coordinationValue,
            keccak256(abi.encodePacked(intent.participants))
        ));
    }

    /**
     * @dev Compute the EIP-712 struct hash for an AcceptanceAttestation.
     */
    function _hashAttestation(
        AcceptanceAttestation calldata attestation
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            ACCEPTANCE_TYPEHASH,
            attestation.intentHash,
            attestation.expiry,
            attestation.agentId
        ));
    }

    /**
     * @dev Compute the hash of a CoordinationPayload.
     */
    function _hashPayload(
        CoordinationPayload calldata payload
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            payload.version,
            payload.coordinationType,
            keccak256(abi.encodePacked(payload.participants)),
            keccak256(payload.coordinationData)
        ));
    }

    /**
     * @dev Verify a signature from an agent (EOA or ERC-1271 contract).
     */
    function _verifySignature(
        address signer,
        bytes32 digest,
        bytes calldata signature
    ) internal view returns (bool) {
        // Try EOA signature first
        if (signer.code.length == 0) {
            address recovered = digest.recover(signature);
            return recovered == signer;
        }

        // Contract signer - use ERC-1271
        try IERC1271(signer).isValidSignature(digest, signature) returns (bytes4 magic) {
            return magic == EIP1271_MAGIC;
        } catch {
            return false;
        }
    }

    /**
     * @dev Get coordination state for internal use.
     */
    function _getCoordination(
        bytes32 intentHash
    ) internal view returns (CoordinationState storage) {
        return _coordinations[intentHash];
    }
}
