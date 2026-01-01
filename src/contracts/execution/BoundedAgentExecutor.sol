// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IBoundedAgentExecutor} from "../interfaces/IBoundedAgentExecutor.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title BoundedAgentExecutor
 * @dev Implementation of bounded agent execution with policy enforcement.
 *
 * Provides trust-minimized execution guardrails for AI agents:
 * - Merkle-proven policy trees restrict allowed operations
 * - Daily spending budgets limit exposure per agent
 * - Timelocked governance prevents instant policy changes
 * - Guardian veto provides emergency protection
 *
 * Key insight: Even if all parties agree (ERC-8001 consensus), bounded
 * limits still apply. Compromised agent = daily budget loss, not total loss.
 */
contract BoundedAgentExecutor is IBoundedAgentExecutor, EIP712, Ownable {
    using ECDSA for bytes32;
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev EIP-712 typehash for BoundedIntent
    bytes32 public constant BOUNDED_INTENT_TYPEHASH = keccak256(
        "BoundedIntent(bytes32 payloadHash,uint64 expiry,uint64 nonce,address agentId,uint256 policyEpoch)"
    );

    /// @dev Domain for policy leaf encoding
    bytes32 public constant POLICY_LEAF_DOMAIN = keccak256("POLICY_LEAF_V1");

    /// @inheritdoc IBoundedAgentExecutor
    uint256 public constant override TIMELOCK_DURATION = 2 days;

    /// @dev 24 hours in seconds
    uint256 private constant DAY = 24 hours;

    // ═══════════════════════════════════════════════════════════════════════════
    // STORAGE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc IBoundedAgentExecutor
    bytes32 public override policyRoot;

    /// @inheritdoc IBoundedAgentExecutor
    uint256 public override policyEpoch;

    /// @dev Queued policy root
    bytes32 public queuedRoot;

    /// @dev When queued policy can be activated
    uint256 public queuedActivationTime;

    /// @dev Guardian address for emergency veto
    address public guardian;

    /// @inheritdoc IBoundedAgentExecutor
    mapping(address => uint64) public override agentNonces;

    /// @dev Agent budgets
    mapping(address => AgentBudget) private _agentBudgets;

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @dev Initializes the executor with initial policy and guardian.
     * @param initialPolicyRoot Initial Merkle root for allowed operations
     * @param _guardian Address that can veto policy updates
     * @param _owner Address that can manage budgets and queue policies
     */
    constructor(
        bytes32 initialPolicyRoot,
        address _guardian,
        address _owner
    ) EIP712("BoundedAgentExecutor", "1") Ownable(_owner) {
        policyRoot = initialPolicyRoot;
        policyEpoch = 1;
        guardian = _guardian;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EXECUTION
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc IBoundedAgentExecutor
    function execute(
        BoundedIntent calldata intent,
        BoundedPayload calldata payload,
        bytes calldata callData,
        bytes calldata signature,
        bytes32[] calldata policyProof
    ) external payable override {
        // Validate intent and get intentHash (scoped to free stack slots)
        bytes32 intentHash = _validateIntent(intent, payload, callData, signature);
        
        // Verify policy proof
        _verifyPolicyProof(payload, policyProof);

        // Check and update budget
        _checkAndUpdateBudget(intent.agentId, payload.amount);

        // Update nonce
        agentNonces[intent.agentId] = intent.nonce;

        // Execute operations
        _executeOperations(payload, callData);

        emit IntentExecuted(intent.agentId, intentHash, payload.target, payload.amount);
    }

    /**
     * @dev Validate intent parameters and signature. Returns intentHash for event.
     */
    function _validateIntent(
        BoundedIntent calldata intent,
        BoundedPayload calldata payload,
        bytes calldata callData,
        bytes calldata signature
    ) internal view returns (bytes32 intentHash) {
        // Validate expiry
        if (intent.expiry <= block.timestamp) {
            revert IntentExpired(intent.expiry, uint64(block.timestamp));
        }

        // Validate nonce
        if (intent.nonce <= agentNonces[intent.agentId]) {
            revert NonceTooLow(intent.nonce, agentNonces[intent.agentId] + 1);
        }

        // Validate policy epoch
        if (intent.policyEpoch != policyEpoch) {
            revert EpochMismatch(policyEpoch, intent.policyEpoch);
        }

        // Validate policy root matches
        if (payload.policyRoot != policyRoot) {
            revert PolicyMismatch(policyRoot, payload.policyRoot);
        }

        // Verify payload hash
        if (intent.payloadHash != _hashPayload(payload)) {
            revert PolicyMismatch(intent.payloadHash, _hashPayload(payload));
        }

        // Verify calldata hash if provided
        if (payload.calldataHash != bytes32(0) && payload.calldataHash != keccak256(callData)) {
            revert PolicyMismatch(payload.calldataHash, keccak256(callData));
        }

        // Verify signature
        intentHash = _hashIntent(intent);
        address recovered = _hashTypedDataV4(intentHash).recover(signature);
        if (recovered != intent.agentId) {
            revert InvalidSignature();
        }
    }

    /**
     * @dev Verify the policy Merkle proof.
     */
    function _verifyPolicyProof(
        BoundedPayload calldata payload,
        bytes32[] calldata policyProof
    ) internal view {
        bytes32 leaf = _computePolicyLeaf(payload.target, payload.asset, payload.amount);
        if (!MerkleProof.verify(policyProof, policyRoot, leaf)) {
            revert InvalidPolicyProof();
        }
    }

    /**
     * @dev Execute token transfer and/or call.
     */
    function _executeOperations(
        BoundedPayload calldata payload,
        bytes calldata callData
    ) internal {
        // Execute ERC20 transfer
        if (payload.asset != address(0) && payload.amount > 0) {
            IERC20(payload.asset).safeTransfer(payload.target, payload.amount);
        }

        // Execute call if calldata provided or native ETH transfer
        // Target is policy-proven, signature-verified, and budget-constrained
        if (callData.length > 0 || payload.asset == address(0)) {
            uint256 ethValue = payload.asset == address(0) ? payload.amount : 0;
            // slither-disable-next-line arbitrary-send-eth
            (bool success,) = payload.target.call{value: ethValue}(callData);
            if (!success) {
                revert CallFailed();
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // POLICY MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc IBoundedAgentExecutor
    function queuePolicyUpdate(bytes32 newRoot) external override onlyOwner {
        queuedRoot = newRoot;
        queuedActivationTime = block.timestamp + TIMELOCK_DURATION;
        
        emit PolicyQueued(newRoot, queuedActivationTime);
    }

    /// @inheritdoc IBoundedAgentExecutor
    function activatePolicy() external override {
        if (queuedRoot == bytes32(0)) {
            revert NoPolicyQueued();
        }
        if (block.timestamp < queuedActivationTime) {
            revert TimelockNotElapsed(queuedActivationTime, block.timestamp);
        }

        policyRoot = queuedRoot;
        policyEpoch++;
        
        emit PolicyActivated(queuedRoot, policyEpoch);

        // Clear queue
        queuedRoot = bytes32(0);
        queuedActivationTime = 0;
    }

    /// @inheritdoc IBoundedAgentExecutor
    function vetoPolicy(bytes32 reason) external override {
        if (msg.sender != guardian) {
            revert NotAuthorized();
        }
        if (queuedRoot == bytes32(0)) {
            revert NoPolicyQueued();
        }

        bytes32 vetoedRoot = queuedRoot;
        queuedRoot = bytes32(0);
        queuedActivationTime = 0;

        emit PolicyVetoed(vetoedRoot, msg.sender);
    }

    /**
     * @notice Update the guardian address.
     * @dev Only callable by owner.
     * @param newGuardian New guardian address
     */
    function setGuardian(address newGuardian) external onlyOwner {
        guardian = newGuardian;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BUDGET MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc IBoundedAgentExecutor
    function setAgentBudget(
        address agentId,
        uint256 dailyLimit
    ) external override onlyOwner {
        _agentBudgets[agentId].dailyLimit = dailyLimit;
        
        emit AgentBudgetSet(agentId, dailyLimit);
    }

    /// @inheritdoc IBoundedAgentExecutor
    function getAgentBudget(
        address agentId
    ) external view override returns (AgentBudget memory) {
        return _agentBudgets[agentId];
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc IBoundedAgentExecutor
    function getQueuedPolicy() external view override returns (
        bytes32 root,
        uint256 activationTime
    ) {
        return (queuedRoot, queuedActivationTime);
    }

    /// @inheritdoc IBoundedAgentExecutor
    function DOMAIN_SEPARATOR() external view override returns (bytes32) {
        return _domainSeparatorV4();
    }

    /// @inheritdoc IBoundedAgentExecutor
    function verifyPolicyProof(
        address target,
        address asset,
        uint256 amount,
        bytes32[] calldata proof
    ) external view override returns (bool) {
        bytes32 leaf = _computePolicyLeaf(target, asset, amount);
        return MerkleProof.verify(proof, policyRoot, leaf);
    }

    /**
     * @notice Get remaining daily budget for an agent.
     * @param agentId The agent address
     * @return remaining Amount remaining in current period
     */
    function getRemainingBudget(address agentId) external view returns (uint256) {
        AgentBudget storage budget = _agentBudgets[agentId];
        
        // Check if period has reset
        if (block.timestamp >= budget.periodStart + DAY) {
            return budget.dailyLimit;
        }
        
        if (budget.spentToday >= budget.dailyLimit) {
            return 0;
        }
        
        return budget.dailyLimit - budget.spentToday;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @dev Check agent budget and update spending.
     */
    function _checkAndUpdateBudget(address agentId, uint256 amount) internal {
        AgentBudget storage budget = _agentBudgets[agentId];
        
        // Reset period if new day
        if (block.timestamp >= budget.periodStart + DAY) {
            budget.spentToday = 0;
            budget.periodStart = block.timestamp;
        }
        
        // Check limit
        uint256 newSpent = budget.spentToday + amount;
        if (newSpent > budget.dailyLimit) {
            revert BudgetExceeded(budget.dailyLimit, amount, budget.spentToday);
        }
        
        budget.spentToday = newSpent;
    }

    /**
     * @dev Compute policy leaf hash.
     */
    function _computePolicyLeaf(
        address target,
        address asset,
        uint256 amount
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(POLICY_LEAF_DOMAIN, target, asset, amount));
    }

    /**
     * @dev Hash BoundedIntent for EIP-712.
     */
    function _hashIntent(BoundedIntent calldata intent) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            BOUNDED_INTENT_TYPEHASH,
            intent.payloadHash,
            intent.expiry,
            intent.nonce,
            intent.agentId,
            intent.policyEpoch
        ));
    }

    /**
     * @dev Hash BoundedPayload.
     */
    function _hashPayload(BoundedPayload calldata payload) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            payload.policyRoot,
            payload.target,
            payload.asset,
            payload.amount,
            payload.calldataHash
        ));
    }

    /**
     * @dev Receive ETH for native token operations.
     */
    receive() external payable {}
}
