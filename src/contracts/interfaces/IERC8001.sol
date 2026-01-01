// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IERC8001
 * @dev Interface for the ERC-8001 Agent Coordination Framework.
 *
 * ERC-8001 defines a minimal, single-chain primitive for multi-party agent coordination.
 * An initiator posts an intent and each participant provides a verifiable acceptance
 * attestation. Once the required set of acceptances is present and fresh, the intent
 * is executable.
 *
 * See https://eips.ethereum.org/EIPS/eip-8001
 */
interface IERC8001 {
    // ═══════════════════════════════════════════════════════════════════════════
    // ENUMS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @dev Coordination lifecycle status.
     */
    enum Status {
        None,       // 0: Intent does not exist
        Proposed,   // 1: Intent proposed, awaiting acceptances
        Ready,      // 2: All participants accepted, executable
        Executed,   // 3: Coordination executed
        Cancelled   // 4: Coordination cancelled
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @dev The core intent structure signed by the proposer.
     * @param payloadHash keccak256 hash of the CoordinationPayload
     * @param expiry Unix timestamp after which the intent is invalid
     * @param nonce Per-agent monotonic nonce for replay protection
     * @param agentId Address of the proposing agent
     * @param coordinationType Domain-specific type identifier
     * @param coordinationValue Optional value associated with coordination
     * @param participants Required participants who must accept
     */
    struct AgentIntent {
        bytes32 payloadHash;
        uint64 expiry;
        uint64 nonce;
        address agentId;
        bytes32 coordinationType;
        uint256 coordinationValue;
        address[] participants;
    }

    /**
     * @dev Acceptance attestation signed by each participant.
     * @param intentHash Hash of the intent being accepted
     * @param expiry Unix timestamp after which the acceptance is invalid
     * @param agentId Address of the accepting agent
     */
    struct AcceptanceAttestation {
        bytes32 intentHash;
        uint64 expiry;
        address agentId;
    }

    /**
     * @dev Application-specific coordination payload.
     * @param version Payload format version
     * @param coordinationType Type identifier matching AgentIntent
     * @param participants Participant addresses matching AgentIntent
     * @param coordinationData Application-specific encoded data
     */
    struct CoordinationPayload {
        bytes32 version;
        bytes32 coordinationType;
        address[] participants;
        bytes coordinationData;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @dev Emitted when a new coordination is proposed.
     * @param intentHash Unique identifier for the coordination
     * @param proposer Address of the proposing agent
     * @param coordinationType Type of coordination
     * @param participants Required participants
     * @param expiry Intent expiration timestamp
     */
    event CoordinationProposed(
        bytes32 indexed intentHash,
        address indexed proposer,
        bytes32 indexed coordinationType,
        address[] participants,
        uint64 expiry
    );

    /**
     * @dev Emitted when a participant accepts a coordination.
     * @param intentHash The coordination being accepted
     * @param participant The accepting agent
     * @param acceptanceCount Current number of acceptances
     * @param totalRequired Total acceptances needed
     */
    event CoordinationAccepted(
        bytes32 indexed intentHash,
        address indexed participant,
        uint256 acceptanceCount,
        uint256 totalRequired
    );

    /**
     * @dev Emitted when a coordination becomes ready for execution.
     * @param intentHash The coordination that is now ready
     */
    event CoordinationReady(bytes32 indexed intentHash);

    /**
     * @dev Emitted when a coordination is executed.
     * @param intentHash The executed coordination
     * @param executor Address that triggered execution
     */
    event CoordinationExecuted(
        bytes32 indexed intentHash,
        address indexed executor
    );

    /**
     * @dev Emitted when a coordination is cancelled.
     * @param intentHash The cancelled coordination
     * @param canceller Address that cancelled
     */
    event CoordinationCancelled(
        bytes32 indexed intentHash,
        address indexed canceller
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Intent has expired
    error IntentExpired(uint64 expiry, uint64 current);

    /// @dev Nonce is not greater than the current nonce
    error NonceTooLow(uint64 provided, uint64 required);

    /// @dev Signature verification failed
    error InvalidSignature(address expected, address recovered);

    /// @dev Intent already exists
    error IntentAlreadyExists(bytes32 intentHash);

    /// @dev Intent does not exist
    error IntentNotFound(bytes32 intentHash);

    /// @dev Acceptance has expired
    error AcceptanceExpired(uint64 expiry, uint64 current);

    /// @dev Participant already accepted
    error AlreadyAccepted(bytes32 intentHash, address participant);

    /// @dev Participant not in required list
    error NotParticipant(bytes32 intentHash, address agent);

    /// @dev Coordination not in Ready status
    error NotReady(bytes32 intentHash, Status current);

    /// @dev Payload hash mismatch
    error PayloadMismatch(bytes32 expected, bytes32 provided);

    /// @dev Not authorized to cancel
    error NotAuthorizedToCancel(bytes32 intentHash, address caller);

    // ═══════════════════════════════════════════════════════════════════════════
    // CORE FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Propose a new multi-party coordination.
     * @dev The proposer MUST sign the intent using EIP-712.
     *      Emits {CoordinationProposed}.
     * @param intent The agent intent structure
     * @param payload The coordination payload (hashed to verify against intent)
     * @param signature EIP-712 signature from the proposer
     * @return intentHash Unique identifier for this coordination
     */
    function proposeCoordination(
        AgentIntent calldata intent,
        CoordinationPayload calldata payload,
        bytes calldata signature
    ) external returns (bytes32 intentHash);

    /**
     * @notice Accept a proposed coordination.
     * @dev The participant MUST sign the acceptance attestation using EIP-712.
     *      When all participants have accepted, status becomes Ready.
     *      Emits {CoordinationAccepted} and optionally {CoordinationReady}.
     * @param intentHash The coordination to accept
     * @param attestation The acceptance attestation
     * @param signature EIP-712 signature from the participant
     */
    function acceptCoordination(
        bytes32 intentHash,
        AcceptanceAttestation calldata attestation,
        bytes calldata signature
    ) external;

    /**
     * @notice Execute a ready coordination.
     * @dev Status MUST be Ready. Execution is application-specific.
     *      Emits {CoordinationExecuted}.
     * @param intentHash The coordination to execute
     * @param payload The coordination payload for execution logic
     * @param executionData Optional execution-specific data
     */
    function executeCoordination(
        bytes32 intentHash,
        CoordinationPayload calldata payload,
        bytes calldata executionData
    ) external;

    /**
     * @notice Cancel a coordination.
     * @dev Only the proposer MAY cancel. Cannot cancel after execution.
     *      Emits {CoordinationCancelled}.
     * @param intentHash The coordination to cancel
     */
    function cancelCoordination(bytes32 intentHash) external;

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get the current status of a coordination.
     * @param intentHash The coordination to query
     * @return status Current lifecycle status
     */
    function getCoordinationStatus(
        bytes32 intentHash
    ) external view returns (Status status);

    /**
     * @notice Get detailed coordination state.
     * @param intentHash The coordination to query
     * @return status Current lifecycle status
     * @return payloadHash Hash of the coordination payload
     * @return participants Required participants
     * @return accepted Participants who have accepted
     * @return expiry Intent expiration timestamp
     */
    function getCoordination(
        bytes32 intentHash
    ) external view returns (
        Status status,
        bytes32 payloadHash,
        address[] memory participants,
        address[] memory accepted,
        uint64 expiry
    );

    /**
     * @notice Get the current nonce for an agent.
     * @param agentId The agent address
     * @return nonce Current nonce value
     */
    function getAgentNonce(address agentId) external view returns (uint64 nonce);

    /**
     * @notice Check if a participant has accepted a coordination.
     * @param intentHash The coordination to check
     * @param participant The participant to check
     * @return hasAccepted True if the participant has accepted
     */
    function hasAccepted(
        bytes32 intentHash,
        address participant
    ) external view returns (bool hasAccepted);

    /**
     * @notice Get the EIP-712 domain separator.
     * @return domainSeparator The domain separator hash
     */
    function DOMAIN_SEPARATOR() external view returns (bytes32 domainSeparator);
}
