// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IBoundedAgentExecutor} from "../interfaces/IBoundedAgentExecutor.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title BoundedAgentExecutor
 * @dev Implementation of bounded agent execution with stronger policy enforcement.
 *
 * Key changes:
 * - Policy leaf binds target + asset + amount + operation mode + selector
 * - Explicit operation modes prevent ambiguous execution semantics
 * - nonReentrant added for defence in depth
 * - Revert data from downstream calls is bubbled up
 */
contract BoundedAgentExecutor is IBoundedAgentExecutor, EIP712, Ownable, ReentrancyGuard {
    using ECDSA for bytes32;
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    bytes32 public constant BOUNDED_INTENT_TYPEHASH = keccak256(
        "BoundedIntent(bytes32 payloadHash,uint64 expiry,uint64 nonce,address agentId,uint256 policyEpoch)"
    );

    bytes32 public constant POLICY_LEAF_DOMAIN = keccak256("POLICY_LEAF_V2");

    uint256 public constant override TIMELOCK_DURATION = 2 days;

    uint256 private constant DAY = 24 hours;

    // ═══════════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════════

    enum OperationMode {
        ERC20_TRANSFER,
        ERC20_TRANSFER_AND_CALL,
        NATIVE_TRANSFER,
        NATIVE_TRANSFER_AND_CALL,
        CALL_ONLY
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STORAGE
    // ═══════════════════════════════════════════════════════════════════════════

    bytes32 public override policyRoot;
    uint256 public override policyEpoch;

    bytes32 public queuedRoot;
    uint256 public queuedActivationTime;

    address public guardian;

    mapping(address => uint64) public override agentNonces;
    mapping(address => AgentBudget) private _agentBudgets;

    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    event GuardianUpdated(address indexed oldGuardian, address indexed newGuardian);
    event PolicyVetoedWithReason(bytes32 indexed vetoedRoot, address indexed guardian, bytes32 reason);

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error InvalidGuardian();
    error InvalidOperationMode();
    error EmptyCalldataNotAllowed();
    error UnexpectedCalldata();
    error SelectorMismatch(bytes4 expected, bytes4 actual);

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    constructor(bytes32 initialPolicyRoot, address _guardian, address _owner)
    EIP712("BoundedAgentExecutor", "1")
    Ownable(_owner)
    {
        if (_guardian == address(0)) revert InvalidGuardian();

        policyRoot = initialPolicyRoot;
        policyEpoch = 1;
        guardian = _guardian;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EXECUTION
    // ═══════════════════════════════════════════════════════════════════════════

    function execute(
        BoundedIntent calldata intent,
        BoundedPayload calldata payload,
        bytes calldata callData,
        bytes calldata signature,
        bytes32[] calldata policyProof
    ) external payable override nonReentrant {
        bytes32 intentHash = _validateIntent(intent, payload, callData, signature);

        _verifyPolicyProof(payload, callData, policyProof);

        _checkAndUpdateBudget(intent.agentId, payload.amount);

        agentNonces[intent.agentId] = intent.nonce;

        _executeOperations(payload, callData);

        emit IntentExecuted(intent.agentId, intentHash, payload.target, payload.amount);
    }

    function _validateIntent(
        BoundedIntent calldata intent,
        BoundedPayload calldata payload,
        bytes calldata callData,
        bytes calldata signature
    ) internal view returns (bytes32 intentHash) {
        if (intent.expiry <= block.timestamp) {
            revert IntentExpired(intent.expiry, uint64(block.timestamp));
        }

        if (intent.nonce <= agentNonces[intent.agentId]) {
            revert NonceTooLow(intent.nonce, agentNonces[intent.agentId] + 1);
        }

        if (intent.policyEpoch != policyEpoch) {
            revert EpochMismatch(policyEpoch, intent.policyEpoch);
        }

        if (payload.policyRoot != policyRoot) {
            revert PolicyMismatch(policyRoot, payload.policyRoot);
        }

        bytes32 computedPayloadHash = _hashPayload(payload);
        if (intent.payloadHash != computedPayloadHash) {
            revert PolicyMismatch(intent.payloadHash, computedPayloadHash);
        }

        if (payload.calldataHash != bytes32(0) && payload.calldataHash != keccak256(callData)) {
            revert PolicyMismatch(payload.calldataHash, keccak256(callData));
        }

        _validateModeAndCalldata(payload, callData);

        intentHash = _hashIntent(intent);
        address recovered = _hashTypedDataV4(intentHash).recover(signature);
        if (recovered != intent.agentId) {
            revert InvalidSignature();
        }
    }

    function _verifyPolicyProof(
        BoundedPayload calldata payload,
        bytes calldata callData,
        bytes32[] calldata policyProof
    ) internal view {
        bytes4 selector = _extractSelector(callData, OperationMode(payload.mode));
        bytes32 leaf = _computePolicyLeaf(
            payload.target,
            payload.asset,
            payload.amount,
            OperationMode(payload.mode),
            selector
        );

        if (!MerkleProof.verify(policyProof, policyRoot, leaf)) {
            revert InvalidPolicyProof();
        }
    }

    function _executeOperations(BoundedPayload calldata payload, bytes calldata callData) internal {
        OperationMode mode = OperationMode(payload.mode);

        if (mode == OperationMode.ERC20_TRANSFER) {
            IERC20(payload.asset).safeTransfer(payload.target, payload.amount);
            return;
        }

        if (mode == OperationMode.ERC20_TRANSFER_AND_CALL) {
            IERC20(payload.asset).safeTransfer(payload.target, payload.amount);
            _callTarget(payload.target, 0, callData);
            return;
        }

        if (mode == OperationMode.NATIVE_TRANSFER) {
            _callTarget(payload.target, payload.amount, "");
            return;
        }

        if (mode == OperationMode.NATIVE_TRANSFER_AND_CALL) {
            _callTarget(payload.target, payload.amount, callData);
            return;
        }

        if (mode == OperationMode.CALL_ONLY) {
            _callTarget(payload.target, 0, callData);
            return;
        }

        revert InvalidOperationMode();
    }

    function _callTarget(address target, uint256 value, bytes calldata callData) internal {
        (bool success, bytes memory returndata) = target.call{value: value}(callData);
        if (!success) {
            _revertWithData(returndata);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // POLICY MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════════

    function queuePolicyUpdate(bytes32 newRoot) external override onlyOwner {
        queuedRoot = newRoot;
        queuedActivationTime = block.timestamp + TIMELOCK_DURATION;

        emit PolicyQueued(newRoot, queuedActivationTime);
    }

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

        queuedRoot = bytes32(0);
        queuedActivationTime = 0;
    }

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
        emit PolicyVetoedWithReason(vetoedRoot, msg.sender, reason);
    }

    function setGuardian(address newGuardian) external onlyOwner {
        if (newGuardian == address(0)) revert InvalidGuardian();

        address oldGuardian = guardian;
        guardian = newGuardian;

        emit GuardianUpdated(oldGuardian, newGuardian);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BUDGET MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════════

    function setAgentBudget(address agentId, uint256 dailyLimit) external override onlyOwner {
        _agentBudgets[agentId].dailyLimit = dailyLimit;

        emit AgentBudgetSet(agentId, dailyLimit);
    }

    function getAgentBudget(address agentId) external view override returns (AgentBudget memory) {
        return _agentBudgets[agentId];
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    function getQueuedPolicy()
    external
    view
    override
    returns (bytes32 root, uint256 activationTime)
    {
        return (queuedRoot, queuedActivationTime);
    }

    function DOMAIN_SEPARATOR() external view override returns (bytes32) {
        return _domainSeparatorV4();
    }

    function verifyPolicyProof(
        address target,
        address asset,
        uint256 amount,
        bytes32[] calldata proof
    ) external view override returns (bool) {
        bytes32 leaf = _computePolicyLeaf(
            target,
            asset,
            amount,
            OperationMode.ERC20_TRANSFER,
            bytes4(0)
        );
        return MerkleProof.verify(proof, policyRoot, leaf);
    }

    function verifyPolicyProofV2(
        address target,
        address asset,
        uint256 amount,
        uint8 mode,
        bytes4 selector,
        bytes32[] calldata proof
    ) external view returns (bool) {
        bytes32 leaf =
                        _computePolicyLeaf(target, asset, amount, OperationMode(mode), selector);
        return MerkleProof.verify(proof, policyRoot, leaf);
    }

    function getRemainingBudget(address agentId) external view returns (uint256) {
        AgentBudget storage budget = _agentBudgets[agentId];

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

    function _checkAndUpdateBudget(address agentId, uint256 amount) internal {
        AgentBudget storage budget = _agentBudgets[agentId];

        if (block.timestamp >= budget.periodStart + DAY) {
            budget.spentToday = 0;
            budget.periodStart = block.timestamp;
        }

        uint256 newSpent = budget.spentToday + amount;
        if (newSpent > budget.dailyLimit) {
            revert BudgetExceeded(budget.dailyLimit, amount, budget.spentToday);
        }

        budget.spentToday = newSpent;
    }

    function _computePolicyLeaf(
        address target,
        address asset,
        uint256 amount,
        OperationMode mode,
        bytes4 selector
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(POLICY_LEAF_DOMAIN, target, asset, amount, mode, selector));
    }

    function _hashIntent(BoundedIntent calldata intent) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                BOUNDED_INTENT_TYPEHASH,
                intent.payloadHash,
                intent.expiry,
                intent.nonce,
                intent.agentId,
                intent.policyEpoch
            )
        );
    }

    function _hashPayload(BoundedPayload calldata payload) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                payload.policyRoot,
                payload.target,
                payload.asset,
                payload.amount,
                payload.calldataHash,
                payload.mode
            )
        );
    }

    function _validateModeAndCalldata(
        BoundedPayload calldata payload,
        bytes calldata callData
    ) internal pure {
        OperationMode mode = OperationMode(payload.mode);

        if (mode == OperationMode.ERC20_TRANSFER) {
            if (payload.asset == address(0)) revert InvalidOperationMode();
            if (callData.length != 0) revert UnexpectedCalldata();
            return;
        }

        if (mode == OperationMode.ERC20_TRANSFER_AND_CALL) {
            if (payload.asset == address(0)) revert InvalidOperationMode();
            if (callData.length < 4) revert EmptyCalldataNotAllowed();
            return;
        }

        if (mode == OperationMode.NATIVE_TRANSFER) {
            if (payload.asset != address(0)) revert InvalidOperationMode();
            if (callData.length != 0) revert UnexpectedCalldata();
            return;
        }

        if (mode == OperationMode.NATIVE_TRANSFER_AND_CALL) {
            if (payload.asset != address(0)) revert InvalidOperationMode();
            if (callData.length < 4) revert EmptyCalldataNotAllowed();
            return;
        }

        if (mode == OperationMode.CALL_ONLY) {
            if (callData.length < 4) revert EmptyCalldataNotAllowed();
            return;
        }

        revert InvalidOperationMode();
    }

    function _extractSelector(bytes calldata callData, OperationMode mode)
    internal
    pure
    returns (bytes4 selector)
    {
        if (
            mode == OperationMode.ERC20_TRANSFER
            || mode == OperationMode.NATIVE_TRANSFER
        ) {
            return bytes4(0);
        }

        if (callData.length < 4) revert EmptyCalldataNotAllowed();

        selector = bytes4(callData[:4]);
    }

    function _revertWithData(bytes memory returndata) internal pure {
        if (returndata.length == 0) {
            revert CallFailed();
        }

        assembly {
            revert(add(returndata, 32), mload(returndata))
        }
    }

    receive() external payable {}
}