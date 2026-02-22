// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {ERC8001} from "../src/contracts/ERC8001.sol";
import {IERC8001} from "../src/contracts/interfaces/IERC8001.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

// ═══════════════════════════════════════════════════════════════════════════
// MOCK IMPLEMENTATION FOR TESTING
// ═══════════════════════════════════════════════════════════════════════════

/**
 * @title MockERC8001
 * @dev A simple mock implementation of ERC8001 for testing the base contract.
 *      This allows testing of core coordination logic without application-specific execution.
 */
contract MockERC8001 is ERC8001 {
    // Track execution results for verification
    mapping(bytes32 => bool) public executionSucceeded;
    mapping(bytes32 => bytes) public executionResults;
    mapping(bytes32 => bool) public wasExecuted;

    constructor() ERC8001() {}

    /**
     * @dev Mock execution that simply records the call and returns success
     */
    function _executeCoordinationHook(
        bytes32 intentHash,
        CoordinationPayload calldata payload,
        bytes calldata executionData
    ) internal override returns (bool success, bytes memory result) {
        // Simple mock: always succeed, return the executionData as result
        wasExecuted[intentHash] = true;
        executionSucceeded[intentHash] = true;
        executionResults[intentHash] = executionData;
        return (true, executionData);
    }

    /**
     * @dev Helper to expose internal state for testing
     */
    function getAcceptedCount(bytes32 intentHash) external view returns (uint256) {
        return _getCoordination(intentHash).acceptedCount;
    }

    /**
     * @dev Helper to check acceptance expiry
     */
    function getAcceptanceExpiry(bytes32 intentHash, address participant) external view returns (uint64) {
        return _getCoordination(intentHash).acceptances[participant].expiry;
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// ERC-8001 BASE CONTRACT TESTS
// ═══════════════════════════════════════════════════════════════════════════

/**
 * @title ERC8001Test
 * @dev Comprehensive tests for the ERC8001 base contract.
 *
 * These tests verify the core coordination framework without application-specific logic.
 */
contract ERC8001Test is Test {
    MockERC8001 public coord;

    // Test participants (sorted ascending by address: bob (0xB0B) < alice (0xA11CE))
    // Note: vm.addr(0xB0B) = 0x243f... < vm.addr(0xA11CE) = 0xe0d2...
    uint256 bobPrivateKey = 0xB0B;
    address bob = vm.addr(bobPrivateKey);

    uint256 alicePrivateKey = 0xA11CE;
    address alice = vm.addr(alicePrivateKey);

    uint256 carolPrivateKey = 0xC0C;
    address carol = vm.addr(carolPrivateKey);

    // EIP-712 typehashes
    bytes32 constant AGENT_INTENT_TYPEHASH = keccak256(
        "AgentIntent(bytes32 payloadHash,uint64 expiry,uint64 nonce,address agentId,bytes32 coordinationType,uint256 coordinationValue,address[] participants)"
    );

    bytes32 constant ACCEPTANCE_TYPEHASH = keccak256(
        "AcceptanceAttestation(bytes32 intentHash,address participant,uint64 nonce,uint64 expiry,bytes32 conditionsHash)"
    );

    function setUp() public {
        coord = new MockERC8001();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PROPOSE COORDINATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Propose_SingleParticipant() public {
        // Single participant coordination (proposer only)
        address[] memory participants = new address[](1);
        participants[0] = alice;

        IERC8001.CoordinationPayload memory payload = _createPayload();

        IERC8001.AgentIntent memory intent = IERC8001.AgentIntent({
            payloadHash: _hashPayload(payload),
            expiry: uint64(block.timestamp + 1 hours),
            nonce: 1,
            agentId: alice,
            coordinationType: keccak256("TEST"),
            coordinationValue: 0,
            participants: participants
        });

        bytes memory signature = _signIntent(intent, alicePrivateKey);
        bytes32 intentHash = coord.proposeCoordination(intent, signature, payload);

        // Verify single participant auto-accepts and becomes Ready
        (IERC8001.Status status,,,,) = coord.getCoordinationStatus(intentHash);
        assertEq(uint256(status), uint256(IERC8001.Status.Ready), "Single participant should be Ready immediately");
        assertEq(coord.getAcceptedCount(intentHash), 1, "Should have 1 acceptance");
        assertEq(coord.hasAccepted(intentHash, alice), true, "Alice should have accepted");
    }

    function test_Propose_MultiParticipant() public {
        // Two participants - proposer auto-accepts but not ready yet
        address[] memory participants = new address[](2);
        participants[0] = bob;
        participants[1] = alice;

        IERC8001.CoordinationPayload memory payload = _createPayload();

        IERC8001.AgentIntent memory intent = IERC8001.AgentIntent({
            payloadHash: _hashPayload(payload),
            expiry: uint64(block.timestamp + 1 hours),
            nonce: 1,
            agentId: alice,
            coordinationType: keccak256("TEST"),
            coordinationValue: 0,
            participants: participants
        });

        bytes memory signature = _signIntent(intent, alicePrivateKey);
        bytes32 intentHash = coord.proposeCoordination(intent, signature, payload);

        // Verify status is Proposed (not Ready, waiting for Bob)
        (IERC8001.Status status,,,,) = coord.getCoordinationStatus(intentHash);
        assertEq(uint256(status), uint256(IERC8001.Status.Proposed), "Should be Proposed, awaiting Bob");
        assertEq(coord.getAcceptedCount(intentHash), 1, "Should have 1 acceptance (Alice)");
        assertEq(coord.hasAccepted(intentHash, alice), true, "Alice should have accepted");
        assertEq(coord.hasAccepted(intentHash, bob), false, "Bob should not have accepted");
    }

    function test_Propose_NonceIncreases() public {
        address[] memory participants = new address[](1);
        participants[0] = alice;

        IERC8001.CoordinationPayload memory payload = _createPayload();

        // First proposal
        IERC8001.AgentIntent memory intent1 = IERC8001.AgentIntent({
            payloadHash: _hashPayload(payload),
            expiry: uint64(block.timestamp + 1 hours),
            nonce: 1,
            agentId: alice,
            coordinationType: keccak256("TEST"),
            coordinationValue: 0,
            participants: participants
        });

        bytes memory signature1 = _signIntent(intent1, alicePrivateKey);
        coord.proposeCoordination(intent1, signature1, payload);

        // Check nonce
        assertEq(coord.getAgentNonce(alice), 1, "Nonce should be 1");

        // Second proposal
        IERC8001.CoordinationPayload memory payload2 = _createPayload();
        IERC8001.AgentIntent memory intent2 = IERC8001.AgentIntent({
            payloadHash: _hashPayload(payload2),
            expiry: uint64(block.timestamp + 2 hours),
            nonce: 2,
            agentId: alice,
            coordinationType: keccak256("TEST2"),
            coordinationValue: 0,
            participants: participants
        });

        bytes memory signature2 = _signIntent(intent2, alicePrivateKey);
        coord.proposeCoordination(intent2, signature2, payload2);

        // Check nonce increased
        assertEq(coord.getAgentNonce(alice), 2, "Nonce should be 2");
    }

    function test_Propose_Revert_NonceTooLow() public {
        // Verify that reusing a nonce after a successful proposal reverts
        address[] memory participants = new address[](1);
        participants[0] = alice;

        IERC8001.CoordinationPayload memory payload = _createPayload();

        IERC8001.AgentIntent memory intent = IERC8001.AgentIntent({
            payloadHash: _hashPayload(payload),
            expiry: uint64(block.timestamp + 1 hours),
            nonce: 1,
            agentId: alice,
            coordinationType: keccak256("TEST"),
            coordinationValue: 0,
            participants: participants
        });

        bytes memory signature = _signIntent(intent, alicePrivateKey);
        coord.proposeCoordination(intent, signature, payload);

        // Build a different intent but reuse nonce 1 — must revert with NonceTooLow
        IERC8001.CoordinationPayload memory payload2 = IERC8001.CoordinationPayload({
            version: keccak256("V2"),
            coordinationType: keccak256("TEST"),
            coordinationData: abi.encode("other data"),
            conditionsHash: bytes32(0),
            timestamp: block.timestamp,
            metadata: ""
        });

        IERC8001.AgentIntent memory intent2 = IERC8001.AgentIntent({
            payloadHash: _hashPayload(payload2),
            expiry: uint64(block.timestamp + 2 hours),
            nonce: 1, // Already used
            agentId: alice,
            coordinationType: keccak256("TEST"),
            coordinationValue: 0,
            participants: participants
        });

        bytes memory signature2 = _signIntent(intent2, alicePrivateKey);
        vm.expectRevert(IERC8001.ERC8001_NonceTooLow.selector);
        coord.proposeCoordination(intent2, signature2, payload2);
    }

    function test_Propose_Revert_AgentNotInParticipants() public {
        address[] memory participants = new address[](1);
        participants[0] = bob; // Only Bob, not Alice

        IERC8001.CoordinationPayload memory payload = _createPayload();

        IERC8001.AgentIntent memory intent = IERC8001.AgentIntent({
            payloadHash: _hashPayload(payload),
            expiry: uint64(block.timestamp + 1 hours),
            nonce: 1,
            agentId: alice, // Alice is proposer but not in participants
            coordinationType: keccak256("TEST"),
            coordinationValue: 0,
            participants: participants
        });

        bytes memory signature = _signIntent(intent, alicePrivateKey);
        
        vm.expectRevert(IERC8001.ERC8001_NotParticipant.selector);
        coord.proposeCoordination(intent, signature, payload);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ACCEPT COORDINATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Accept_Success() public {
        // Setup: Alice proposes, Bob needs to accept
        address[] memory participants = new address[](2);
        participants[0] = bob;
        participants[1] = alice;

        IERC8001.CoordinationPayload memory payload = _createPayload();

        IERC8001.AgentIntent memory intent = IERC8001.AgentIntent({
            payloadHash: _hashPayload(payload),
            expiry: uint64(block.timestamp + 1 hours),
            nonce: 1,
            agentId: alice,
            coordinationType: keccak256("TEST"),
            coordinationValue: 0,
            participants: participants
        });

        bytes32 intentHash = _hashIntent(intent);
        bytes memory signature = _signIntent(intent, alicePrivateKey);
        coord.proposeCoordination(intent, signature, payload);

        // Bob accepts
        IERC8001.AcceptanceAttestation memory acceptance = IERC8001.AcceptanceAttestation({
            intentHash: intentHash,
            participant: bob,
            nonce: 1,
            expiry: uint64(block.timestamp + 30 minutes),
            conditionsHash: bytes32(0),
            signature: ""
        });

        bytes memory bobSignature = _signAcceptance(acceptance, bobPrivateKey);
        acceptance.signature = bobSignature;

        vm.prank(bob);
        bool allAccepted = coord.acceptCoordination(intentHash, acceptance);

        assertTrue(allAccepted, "Should report all accepted");
        assertEq(coord.getAcceptedCount(intentHash), 2, "Should have 2 acceptances");
        assertEq(coord.hasAccepted(intentHash, bob), true, "Bob should have accepted");

        // Status should now be Ready
        (IERC8001.Status status,,,,) = coord.getCoordinationStatus(intentHash);
        assertEq(uint256(status), uint256(IERC8001.Status.Ready), "Should be Ready");
    }

    function test_Accept_Revert_NotParticipant() public {
        address[] memory participants = new address[](2);
        participants[0] = bob;
        participants[1] = alice;

        IERC8001.CoordinationPayload memory payload = _createPayload();

        IERC8001.AgentIntent memory intent = IERC8001.AgentIntent({
            payloadHash: _hashPayload(payload),
            expiry: uint64(block.timestamp + 1 hours),
            nonce: 1,
            agentId: alice,
            coordinationType: keccak256("TEST"),
            coordinationValue: 0,
            participants: participants
        });

        bytes32 intentHash = _hashIntent(intent);
        bytes memory signature = _signIntent(intent, alicePrivateKey);
        coord.proposeCoordination(intent, signature, payload);

        // Carol (not a participant) tries to accept
        IERC8001.AcceptanceAttestation memory acceptance = IERC8001.AcceptanceAttestation({
            intentHash: intentHash,
            participant: carol,
            nonce: 1,
            expiry: uint64(block.timestamp + 30 minutes),
            conditionsHash: bytes32(0),
            signature: ""
        });

        bytes memory carolSignature = _signAcceptance(acceptance, carolPrivateKey);
        acceptance.signature = carolSignature;

        vm.expectRevert(IERC8001.ERC8001_NotParticipant.selector);
        vm.prank(carol);
        coord.acceptCoordination(intentHash, acceptance);
    }

    function test_Accept_Revert_WrongCaller() public {
        address[] memory participants = new address[](2);
        participants[0] = bob;
        participants[1] = alice;

        IERC8001.CoordinationPayload memory payload = _createPayload();

        IERC8001.AgentIntent memory intent = IERC8001.AgentIntent({
            payloadHash: _hashPayload(payload),
            expiry: uint64(block.timestamp + 1 hours),
            nonce: 1,
            agentId: alice,
            coordinationType: keccak256("TEST"),
            coordinationValue: 0,
            participants: participants
        });

        bytes32 intentHash = _hashIntent(intent);
        bytes memory signature = _signIntent(intent, alicePrivateKey);
        coord.proposeCoordination(intent, signature, payload);

        // Bob signs, but Carol calls (wrong msg.sender)
        IERC8001.AcceptanceAttestation memory acceptance = IERC8001.AcceptanceAttestation({
            intentHash: intentHash,
            participant: bob,
            nonce: 1,
            expiry: uint64(block.timestamp + 30 minutes),
            conditionsHash: bytes32(0),
            signature: ""
        });

        bytes memory bobSignature = _signAcceptance(acceptance, bobPrivateKey);
        acceptance.signature = bobSignature;

        vm.expectRevert(IERC8001.ERC8001_NotParticipant.selector);
        vm.prank(carol); // Wrong caller
        coord.acceptCoordination(intentHash, acceptance);
    }

    function test_Accept_Revert_AlreadyAccepted() public {
        address[] memory participants = new address[](1);
        participants[0] = alice;

        IERC8001.CoordinationPayload memory payload = _createPayload();

        IERC8001.AgentIntent memory intent = IERC8001.AgentIntent({
            payloadHash: _hashPayload(payload),
            expiry: uint64(block.timestamp + 1 hours),
            nonce: 1,
            agentId: alice,
            coordinationType: keccak256("TEST"),
            coordinationValue: 0,
            participants: participants
        });

        bytes32 intentHash = _hashIntent(intent);
        bytes memory signature = _signIntent(intent, alicePrivateKey);
        coord.proposeCoordination(intent, signature, payload);

        // Alice tries to accept again (already auto-accepted)
        IERC8001.AcceptanceAttestation memory acceptance = IERC8001.AcceptanceAttestation({
            intentHash: intentHash,
            participant: alice,
            nonce: 1,
            expiry: uint64(block.timestamp + 30 minutes),
            conditionsHash: bytes32(0),
            signature: ""
        });

        bytes memory aliceSignature = _signAcceptance(acceptance, alicePrivateKey);
        acceptance.signature = aliceSignature;

        vm.expectRevert(IERC8001.ERC8001_DuplicateAcceptance.selector);
        vm.prank(alice);
        coord.acceptCoordination(intentHash, acceptance);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EXECUTE COORDINATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Execute_Success() public {
        address[] memory participants = new address[](1);
        participants[0] = alice;

        IERC8001.CoordinationPayload memory payload = _createPayload();

        IERC8001.AgentIntent memory intent = IERC8001.AgentIntent({
            payloadHash: _hashPayload(payload),
            expiry: uint64(block.timestamp + 1 hours),
            nonce: 1,
            agentId: alice,
            coordinationType: keccak256("TEST"),
            coordinationValue: 0,
            participants: participants
        });

        bytes memory signature = _signIntent(intent, alicePrivateKey);
        bytes32 intentHash = coord.proposeCoordination(intent, signature, payload);

        // Execute
        bytes memory executionData = abi.encode("test result");
        (bool success, bytes memory result) = coord.executeCoordination(intentHash, payload, executionData);

        assertTrue(success, "Execution should succeed");
        assertEq(result, executionData, "Result should match execution data");
        assertTrue(coord.wasExecuted(intentHash), "Should record execution");
        assertTrue(coord.executionSucceeded(intentHash), "Should record success");

        // Verify status is Executed
        (IERC8001.Status status,,,,) = coord.getCoordinationStatus(intentHash);
        assertEq(uint256(status), uint256(IERC8001.Status.Executed), "Should be Executed");
    }

    function test_Execute_Revert_NotReady() public {
        address[] memory participants = new address[](2);
        participants[0] = bob;
        participants[1] = alice;

        IERC8001.CoordinationPayload memory payload = _createPayload();

        IERC8001.AgentIntent memory intent = IERC8001.AgentIntent({
            payloadHash: _hashPayload(payload),
            expiry: uint64(block.timestamp + 1 hours),
            nonce: 1,
            agentId: alice,
            coordinationType: keccak256("TEST"),
            coordinationValue: 0,
            participants: participants
        });

        bytes memory signature = _signIntent(intent, alicePrivateKey);
        bytes32 intentHash = coord.proposeCoordination(intent, signature, payload);

        // Bob hasn't accepted yet - try to execute
        vm.expectRevert(IERC8001.ERC8001_NotReady.selector);
        coord.executeCoordination(intentHash, payload, "");
    }

    function test_Execute_Revert_AlreadyExecuted() public {
        address[] memory participants = new address[](1);
        participants[0] = alice;

        IERC8001.CoordinationPayload memory payload = _createPayload();

        IERC8001.AgentIntent memory intent = IERC8001.AgentIntent({
            payloadHash: _hashPayload(payload),
            expiry: uint64(block.timestamp + 1 hours),
            nonce: 1,
            agentId: alice,
            coordinationType: keccak256("TEST"),
            coordinationValue: 0,
            participants: participants
        });

        bytes memory signature = _signIntent(intent, alicePrivateKey);
        bytes32 intentHash = coord.proposeCoordination(intent, signature, payload);

        // Execute once
        coord.executeCoordination(intentHash, payload, "");

        // Try to execute again
        vm.expectRevert(IERC8001.ERC8001_NotReady.selector);
        coord.executeCoordination(intentHash, payload, "");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CANCEL COORDINATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Cancel_ByProposer_BeforeExpiry() public {
        address[] memory participants = new address[](2);
        participants[0] = bob;
        participants[1] = alice;

        IERC8001.CoordinationPayload memory payload = _createPayload();

        IERC8001.AgentIntent memory intent = IERC8001.AgentIntent({
            payloadHash: _hashPayload(payload),
            expiry: uint64(block.timestamp + 1 hours),
            nonce: 1,
            agentId: alice,
            coordinationType: keccak256("TEST"),
            coordinationValue: 0,
            participants: participants
        });

        bytes memory signature = _signIntent(intent, alicePrivateKey);
        bytes32 intentHash = coord.proposeCoordination(intent, signature, payload);

        // Alice (proposer) cancels before expiry
        vm.prank(alice);
        coord.cancelCoordination(intentHash, "Changed my mind");

        // Verify status
        (IERC8001.Status status,,,,) = coord.getCoordinationStatus(intentHash);
        assertEq(uint256(status), uint256(IERC8001.Status.Cancelled), "Should be Cancelled");
    }

    function test_Cancel_ByAnyone_AfterExpiry() public {
        address[] memory participants = new address[](2);
        participants[0] = bob;
        participants[1] = alice;

        IERC8001.CoordinationPayload memory payload = _createPayload();

        IERC8001.AgentIntent memory intent = IERC8001.AgentIntent({
            payloadHash: _hashPayload(payload),
            expiry: uint64(block.timestamp + 1 hours),
            nonce: 1,
            agentId: alice,
            coordinationType: keccak256("TEST"),
            coordinationValue: 0,
            participants: participants
        });

        bytes memory signature = _signIntent(intent, alicePrivateKey);
        bytes32 intentHash = coord.proposeCoordination(intent, signature, payload);

        // Move past expiry
        vm.warp(block.timestamp + 2 hours);

        // Bob (not proposer) can cancel after expiry
        vm.prank(bob);
        coord.cancelCoordination(intentHash, "Expired");

        (IERC8001.Status status,,,,) = coord.getCoordinationStatus(intentHash);
        assertEq(uint256(status), uint256(IERC8001.Status.Cancelled), "Should be Cancelled");
    }

    function test_Cancel_Revert_NonProposer_BeforeExpiry() public {
        address[] memory participants = new address[](2);
        participants[0] = bob;
        participants[1] = alice;

        IERC8001.CoordinationPayload memory payload = _createPayload();

        IERC8001.AgentIntent memory intent = IERC8001.AgentIntent({
            payloadHash: _hashPayload(payload),
            expiry: uint64(block.timestamp + 1 hours),
            nonce: 1,
            agentId: alice,
            coordinationType: keccak256("TEST"),
            coordinationValue: 0,
            participants: participants
        });

        bytes memory signature = _signIntent(intent, alicePrivateKey);
        bytes32 intentHash = coord.proposeCoordination(intent, signature, payload);

        // Bob (not proposer) tries to cancel before expiry
        vm.expectRevert(IERC8001.ERC8001_NotProposer.selector);
        vm.prank(bob);
        coord.cancelCoordination(intentHash, "Changed my mind");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STATUS TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_GetCoordinationStatus_DynamicExpired() public {
        address[] memory participants = new address[](1);
        participants[0] = alice;

        IERC8001.CoordinationPayload memory payload = _createPayload();

        IERC8001.AgentIntent memory intent = IERC8001.AgentIntent({
            payloadHash: _hashPayload(payload),
            expiry: uint64(block.timestamp + 1 hours),
            nonce: 1,
            agentId: alice,
            coordinationType: keccak256("TEST"),
            coordinationValue: 0,
            participants: participants
        });

        bytes memory signature = _signIntent(intent, alicePrivateKey);
        bytes32 intentHash = coord.proposeCoordination(intent, signature, payload);

        // Initially Ready
        (IERC8001.Status status1,,,,) = coord.getCoordinationStatus(intentHash);
        assertEq(uint256(status1), uint256(IERC8001.Status.Ready), "Should be Ready initially");

        // Move past expiry
        vm.warp(block.timestamp + 2 hours);

        // Should report Expired dynamically
        (IERC8001.Status status2,,,,) = coord.getCoordinationStatus(intentHash);
        assertEq(uint256(status2), uint256(IERC8001.Status.Expired), "Should report Expired dynamically");
    }

    function test_GetCoordinationStatus_FullDetails() public {
        address[] memory participants = new address[](2);
        participants[0] = bob;
        participants[1] = alice;

        IERC8001.CoordinationPayload memory payload = _createPayload();

        IERC8001.AgentIntent memory intent = IERC8001.AgentIntent({
            payloadHash: _hashPayload(payload),
            expiry: uint64(block.timestamp + 1 hours),
            nonce: 1,
            agentId: alice,
            coordinationType: keccak256("TEST"),
            coordinationValue: 100,
            participants: participants
        });

        bytes memory signature = _signIntent(intent, alicePrivateKey);
        bytes32 intentHash = coord.proposeCoordination(intent, signature, payload);

        (
            IERC8001.Status status,
            address proposer,
            address[] memory storedParticipants,
            address[] memory acceptedBy,
            uint256 expiry
        ) = coord.getCoordinationStatus(intentHash);

        // participants stored in the order they were provided: [bob, alice]
        assertEq(uint256(status), uint256(IERC8001.Status.Proposed));
        assertEq(proposer, alice);
        assertEq(storedParticipants.length, 2);
        assertEq(storedParticipants[0], bob);
        assertEq(storedParticipants[1], alice);
        assertEq(acceptedBy.length, 1);
        assertEq(acceptedBy[0], alice);
        assertEq(expiry, block.timestamp + 1 hours);
    }

    function test_GetRequiredAcceptances() public {
        // Sort all three addresses ascending to satisfy canonicalization
        address[] memory unsorted = new address[](3);
        unsorted[0] = alice;
        unsorted[1] = bob;
        unsorted[2] = carol;
        address[] memory participants = _sortAscending(unsorted);

        // agentId must be in participants list; use whoever ends up there
        // alice is always in the sorted list since it's just a reorder
        IERC8001.CoordinationPayload memory payload = _createPayload();

        IERC8001.AgentIntent memory intent = IERC8001.AgentIntent({
            payloadHash: _hashPayload(payload),
            expiry: uint64(block.timestamp + 1 hours),
            nonce: 1,
            agentId: alice,
            coordinationType: keccak256("TEST"),
            coordinationValue: 0,
            participants: participants
        });

        bytes memory signature = _signIntent(intent, alicePrivateKey);
        bytes32 intentHash = coord.proposeCoordination(intent, signature, payload);

        assertEq(coord.getRequiredAcceptances(intentHash), 3, "Should require 3 acceptances");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DOMAIN SEPARATOR TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_DomainSeparator() public {
        bytes32 domainSeparator = coord.DOMAIN_SEPARATOR();
        assertTrue(domainSeparator != bytes32(0), "Domain separator should be non-zero");

        // Verify it matches expected EIP-712 domain
        bytes32 expectedDomain = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("ERC-8001")),
                keccak256(bytes("1")),
                block.chainid,
                address(coord)
            )
        );

        assertEq(domainSeparator, expectedDomain, "Domain separator should match expected");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EVENT TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Events_CoordinationProposed() public {
        address[] memory participants = new address[](2);
        participants[0] = bob;
        participants[1] = alice;

        IERC8001.CoordinationPayload memory payload = _createPayload();

        IERC8001.AgentIntent memory intent = IERC8001.AgentIntent({
            payloadHash: _hashPayload(payload),
            expiry: uint64(block.timestamp + 1 hours),
            nonce: 1,
            agentId: alice,
            coordinationType: keccak256("TEST_TYPE"),
            coordinationValue: 100,
            participants: participants
        });

        bytes memory signature = _signIntent(intent, alicePrivateKey);

        // Expect event
        vm.expectEmit(true, true, false, true);
        emit IERC8001.CoordinationProposed(
            _hashIntent(intent),
            alice,
            keccak256("TEST_TYPE"),
            2, // participantCount
            100 // coordinationValue
        );

        coord.proposeCoordination(intent, signature, payload);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // HELPER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    function _createPayload() internal view returns (IERC8001.CoordinationPayload memory) {
        return IERC8001.CoordinationPayload({
            version: keccak256("V1"),
            coordinationType: keccak256("TEST"),
            coordinationData: abi.encode("test data"),
            conditionsHash: bytes32(0),
            timestamp: block.timestamp,
            metadata: ""
        });
    }

    function _hashPayload(IERC8001.CoordinationPayload memory payload) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                payload.version,
                payload.coordinationType,
                keccak256(payload.coordinationData),
                payload.conditionsHash,
                payload.timestamp,
                keccak256(payload.metadata)
            )
        );
    }

    function _hashIntent(IERC8001.AgentIntent memory intent) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                AGENT_INTENT_TYPEHASH,
                intent.payloadHash,
                intent.expiry,
                intent.nonce,
                intent.agentId,
                intent.coordinationType,
                intent.coordinationValue,
                keccak256(abi.encodePacked(intent.participants))
            )
        );
    }

    function _signIntent(IERC8001.AgentIntent memory intent, uint256 privateKey) internal view returns (bytes memory) {
        bytes32 structHash = _hashIntent(intent);
        bytes32 digest = MessageHashUtils.toTypedDataHash(coord.DOMAIN_SEPARATOR(), structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function _hashAttestation(IERC8001.AcceptanceAttestation memory attestation) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                ACCEPTANCE_TYPEHASH,
                attestation.intentHash,
                attestation.participant,
                attestation.nonce,
                attestation.expiry,
                attestation.conditionsHash
            )
        );
    }

    function _signAcceptance(IERC8001.AcceptanceAttestation memory attestation, uint256 privateKey) internal view returns (bytes memory) {
        bytes32 structHash = _hashAttestation(attestation);
        bytes32 digest = MessageHashUtils.toTypedDataHash(coord.DOMAIN_SEPARATOR(), structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    /// @dev Simple insertion sort for ascending address ordering (per ERC-8001 spec)
    function _sortAscending(address[] memory addrs) internal pure returns (address[] memory) {
        uint256 n = addrs.length;
        for (uint256 i = 1; i < n; i++) {
            address key = addrs[i];
            uint256 j = i;
            while (j > 0 && uint160(addrs[j - 1]) > uint160(key)) {
                addrs[j] = addrs[j - 1];
                j--;
            }
            addrs[j] = key;
        }
        return addrs;
    }
}
