// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IBoundedAgentExecutor
 * @dev Interface for bounded agent execution with policy enforcement.
 */
interface IBoundedAgentExecutor {
    // ═══════════════════════════════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @dev Intent signed by an agent requesting execution.
     */
    struct BoundedIntent {
        bytes32 payloadHash;    // Hash of the payload
        uint64 expiry;          // When intent expires
        uint64 nonce;           // Replay protection
        address agentId;        // Agent signing the intent
        uint256 policyEpoch;    // Policy version this was signed against
    }

    /**
     * @dev Payload containing execution details.
     */
    struct BoundedPayload {
        bytes32 policyRoot;     // Expected policy root
        address target;         // Target contract/address
        address asset;          // Token address (address(0) for ETH)
        uint256 amount;         // Amount to transfer
        bytes32 calldataHash;   // Hash of calldata (bytes32(0) if none)
    }

    /**
     * @dev Agent budget tracking.
     */
    struct AgentBudget {
        uint256 dailyLimit;     // Maximum daily spend
        uint256 spentToday;     // Amount spent in current period
        uint256 periodStart;    // When current period started
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    event IntentExecuted(
        address indexed agentId,
        bytes32 indexed intentHash,
        address target,
        uint256 amount
    );

    event PolicyQueued(bytes32 indexed newRoot, uint256 activationTime);
    event PolicyActivated(bytes32 indexed newRoot, uint256 epoch);
    event PolicyVetoed(bytes32 indexed vetoedRoot, address indexed vetoer);
    event AgentBudgetSet(address indexed agentId, uint256 dailyLimit);

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error IntentExpired(uint64 expiry, uint64 currentTime);
    error NonceTooLow(uint64 provided, uint64 required);
    error EpochMismatch(uint256 current, uint256 provided);
    error PolicyMismatch(bytes32 expected, bytes32 provided);
    error InvalidSignature();
    error InvalidPolicyProof();
    error BudgetExceeded(uint256 limit, uint256 requested, uint256 spent);
    error CallFailed();
    error NoPolicyQueued();
    error TimelockNotElapsed(uint256 required, uint256 current);
    error NotAuthorized();

    // ═══════════════════════════════════════════════════════════════════════════
    // FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Execute a bounded intent.
     */
    function execute(
        BoundedIntent calldata intent,
        BoundedPayload calldata payload,
        bytes calldata callData,
        bytes calldata signature,
        bytes32[] calldata policyProof
    ) external payable;

    /**
     * @notice Queue a policy update (subject to timelock).
     */
    function queuePolicyUpdate(bytes32 newRoot) external;

    /**
     * @notice Activate a queued policy after timelock.
     */
    function activatePolicy() external;

    /**
     * @notice Veto a queued policy (guardian only).
     */
    function vetoPolicy(bytes32 reason) external;

    /**
     * @notice Set daily budget for an agent.
     */
    function setAgentBudget(address agentId, uint256 dailyLimit) external;

    /**
     * @notice Get agent budget info.
     */
    function getAgentBudget(address agentId) external view returns (AgentBudget memory);

    /**
     * @notice Get queued policy info.
     */
    function getQueuedPolicy() external view returns (bytes32 root, uint256 activationTime);

    /**
     * @notice Verify a policy proof.
     */
    function verifyPolicyProof(
        address target,
        address asset,
        uint256 amount,
        bytes32[] calldata proof
    ) external view returns (bool);

    /**
     * @notice Get EIP-712 domain separator.
     */
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    /**
     * @notice Current policy root.
     */
    function policyRoot() external view returns (bytes32);

    /**
     * @notice Current policy epoch.
     */
    function policyEpoch() external view returns (uint256);

    /**
     * @notice Timelock duration for policy updates.
     */
    function TIMELOCK_DURATION() external view returns (uint256);

    /**
     * @notice Get agent nonce.
     */
    function agentNonces(address agent) external view returns (uint64);
}
