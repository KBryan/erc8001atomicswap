// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {AtomicSwap} from "../src/contracts/examples/AtomicSwap.sol";
import {IERC8001} from "../src/contracts/interfaces/IERC8001.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

// ═══════════════════════════════════════════════════════════════════════════
// MOCK TOKENS
// ═══════════════════════════════════════════════════════════════════════════

contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

contract MockWETH is ERC20 {
    constructor() ERC20("Wrapped Ether", "WETH") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// TEST: ERC-8001 COMPLIANCE
// ═══════════════════════════════════════════════════════════════════════════

/**
 * @title AtomicSwapTest
 * @dev Comprehensive tests for ERC-8001 compliance.
 */
contract AtomicSwapTest is Test {
    AtomicSwap public swap;
    MockUSDC public usdc;
    MockWETH public weth;

    // Participants (sorted by uint160: bob < alice)
    // bob's address (from 0xB0B): 0x243f... 
    // alice's address (from 0xA11CE): 0xe0d2...
    uint256 bobPrivateKey = 0xB0B;
    address bob = vm.addr(bobPrivateKey);

    uint256 alicePrivateKey = 0xA11CE;
    address alice = vm.addr(alicePrivateKey);

    // Swap amounts
    uint256 constant USDC_AMOUNT = 100 * 1e6;  // 100 USDC
    uint256 constant WETH_AMOUNT = 0.05 ether;  // 0.05 WETH

    // EIP-712 typehashes (matching spec exactly)
    bytes32 constant AGENT_INTENT_TYPEHASH = keccak256(
        "AgentIntent(bytes32 payloadHash,uint64 expiry,uint64 nonce,address agentId,bytes32 coordinationType,uint256 coordinationValue,address[] participants)"
    );

    bytes32 constant ACCEPTANCE_TYPEHASH = keccak256(
        "AcceptanceAttestation(bytes32 intentHash,address participant,uint64 nonce,uint64 expiry,bytes32 conditionsHash)"
    );

    function setUp() public {
        swap = new AtomicSwap();
        usdc = new MockUSDC();
        weth = new MockWETH();

        // Fund participants
        usdc.mint(alice, USDC_AMOUNT);
        weth.mint(bob, WETH_AMOUNT);

        // Approve swap contract
        vm.prank(alice);
        usdc.approve(address(swap), USDC_AMOUNT);

        vm.prank(bob);
        weth.approve(address(swap), WETH_AMOUNT);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // HAPPY PATH TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_HelloWorld_AtomicSwap() public {
        // Build swap terms
        bytes memory coordinationData = swap.encodeSwapTerms(
            address(usdc), USDC_AMOUNT,
            address(weth), WETH_AMOUNT
        );

        // Participants must be in ascending order (per spec): bob < alice
        address[] memory participants = new address[](2);
        participants[0] = bob;
        participants[1] = alice;

        // Build payload (new struct shape per spec)
        IERC8001.CoordinationPayload memory payload = IERC8001.CoordinationPayload({
            version: keccak256("V1"),
            coordinationType: swap.SWAP_TYPE(),
            coordinationData: coordinationData,
            conditionsHash: bytes32(0),
            timestamp: block.timestamp,
            metadata: ""
        });

        // Build intent
        IERC8001.AgentIntent memory intent = IERC8001.AgentIntent({
            payloadHash: _hashPayload(payload),
            expiry: uint64(block.timestamp + 1 hours),
            nonce: 1,
            agentId: alice,
            coordinationType: swap.SWAP_TYPE(),
            coordinationValue: 0,
            participants: participants
        });

        // Alice signs and proposes
        bytes memory aliceSignature = _signIntent(intent);
        bytes32 intentHash = swap.proposeCoordination(intent, aliceSignature, payload);

        console2.log("Step 1: Alice proposed swap");
        console2.log("  Intent hash:", vm.toString(intentHash));

        // Verify status
        (
            IERC8001.Status status,
            address proposer,
            address[] memory storedParticipants,
            address[] memory acceptedBy,
            uint256 expiry
        ) = swap.getCoordinationStatus(intentHash);

        assertEq(uint256(status), uint256(IERC8001.Status.Proposed), "Should be Proposed (awaiting bob's acceptance)");
        assertEq(proposer, alice);
        assertEq(storedParticipants.length, 2);
        assertEq(acceptedBy.length, 1);
        assertEq(acceptedBy[0], alice);

        // Bob accepts
        IERC8001.AcceptanceAttestation memory acceptance = IERC8001.AcceptanceAttestation({
            intentHash: intentHash,
            participant: bob,
            nonce: 1,
            expiry: uint64(block.timestamp + 1 hours),
            conditionsHash: bytes32(0),
            signature: ""
        });

        bytes memory bobSignature = _signAcceptance(acceptance);
        acceptance.signature = bobSignature;

        vm.prank(bob);
        bool allAccepted = swap.acceptCoordination(intentHash, acceptance);

        assertTrue(allAccepted, "All should accept");
        console2.log("Step 2: Bob accepted swap");

        // Execute
        uint256 aliceUsdcBefore = usdc.balanceOf(alice);
        uint256 aliceWethBefore = weth.balanceOf(alice);
        uint256 bobUsdcBefore = usdc.balanceOf(bob);
        uint256 bobWethBefore = weth.balanceOf(bob);

        (bool success, bytes memory result) = swap.executeCoordination(intentHash, payload, "");

        assertTrue(success, "Execution should succeed");
        console2.log("Step 3: Swap executed!");

        // Verify balances
        assertEq(usdc.balanceOf(alice), aliceUsdcBefore - USDC_AMOUNT, "Alice should send USDC");
        assertEq(weth.balanceOf(alice), aliceWethBefore + WETH_AMOUNT, "Alice should receive WETH");
        assertEq(weth.balanceOf(bob), bobWethBefore - WETH_AMOUNT, "Bob should send WETH");
        assertEq(usdc.balanceOf(bob), bobUsdcBefore + USDC_AMOUNT, "Bob should receive USDC");

        // Verify final status
        (IERC8001.Status finalStatus,,,,) = swap.getCoordinationStatus(intentHash);
        assertEq(uint256(finalStatus), uint256(IERC8001.Status.Executed), "Should be Executed");

        console2.log("");
        console2.log("=== SWAP COMPLETE ===");
        console2.log("Alice: -100 USDC, +0.05 WETH");
        console2.log("Bob:   +100 USDC, -0.05 WETH");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FAILURE MODE TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_ExpiredIntent_Reverts() public {
        // Create intent already expired
        address[] memory participants = new address[](2);
        participants[0] = bob;
        participants[1] = alice;

        IERC8001.CoordinationPayload memory payload = IERC8001.CoordinationPayload({
            version: keccak256("V1"),
            coordinationType: swap.SWAP_TYPE(),
            coordinationData: swap.encodeSwapTerms(address(usdc), USDC_AMOUNT, address(weth), WETH_AMOUNT),
            conditionsHash: bytes32(0),
            timestamp: block.timestamp,
            metadata: ""
        });

        IERC8001.AgentIntent memory intent = IERC8001.AgentIntent({
            payloadHash: _hashPayload(payload),
            expiry: uint64(block.timestamp - 1), // Already expired
            nonce: 1,
            agentId: alice,
            coordinationType: swap.SWAP_TYPE(),
            coordinationValue: 0,
            participants: participants
        });

        bytes memory signature = _signIntent(intent);

        vm.expectRevert(abi.encodeWithSelector(IERC8001.ERC8001_ExpiredIntent.selector));
        swap.proposeCoordination(intent, signature, payload);
    }

    function test_NonCanonicalParticipants_Reverts() public {
        // Participants not in ascending order
        address[] memory participants = new address[](2);
        participants[0] = alice;  // Higher address first (0xe0d2...)
        participants[1] = bob;   // Lower address second (0x243f...) - not canonical!

        IERC8001.CoordinationPayload memory payload = IERC8001.CoordinationPayload({
            version: keccak256("V1"),
            coordinationType: swap.SWAP_TYPE(),
            coordinationData: swap.encodeSwapTerms(address(usdc), USDC_AMOUNT, address(weth), WETH_AMOUNT),
            conditionsHash: bytes32(0),
            timestamp: block.timestamp,
            metadata: ""
        });

        IERC8001.AgentIntent memory intent = IERC8001.AgentIntent({
            payloadHash: _hashPayload(payload),
            expiry: uint64(block.timestamp + 1 hours),
            nonce: 1,
            agentId: alice,
            coordinationType: swap.SWAP_TYPE(),
            coordinationValue: 0,
            participants: participants
        });

        bytes memory signature = _signIntent(intent);

        vm.expectRevert(abi.encodeWithSelector(IERC8001.ERC8001_ParticipantsNotCanonical.selector));
        swap.proposeCoordination(intent, signature, payload);
    }

    function test_AgentIdNotParticipant_Reverts() public {
        address[] memory participants = new address[](2);
        participants[0] = bob;
        participants[1] = alice;

        IERC8001.CoordinationPayload memory payload = IERC8001.CoordinationPayload({
            version: keccak256("V1"),
            coordinationType: swap.SWAP_TYPE(),
            coordinationData: swap.encodeSwapTerms(address(usdc), USDC_AMOUNT, address(weth), WETH_AMOUNT),
            conditionsHash: bytes32(0),
            timestamp: block.timestamp,
            metadata: ""
        });

        IERC8001.AgentIntent memory intent = IERC8001.AgentIntent({
            payloadHash: _hashPayload(payload),
            expiry: uint64(block.timestamp + 1 hours),
            nonce: 1,
            agentId: address(0xBAD), // Not in participants
            coordinationType: swap.SWAP_TYPE(),
            coordinationValue: 0,
            participants: participants
        });

        bytes memory signature = _signIntentForAddress(intent, address(0xBAD), 0xBAD);

        vm.expectRevert(abi.encodeWithSelector(IERC8001.ERC8001_NotParticipant.selector));
        swap.proposeCoordination(intent, signature, payload);
    }

    function test_BadSignature_Reverts() public {
        address[] memory participants = new address[](2);
        participants[0] = bob;
        participants[1] = alice;

        IERC8001.CoordinationPayload memory payload = IERC8001.CoordinationPayload({
            version: keccak256("V1"),
            coordinationType: swap.SWAP_TYPE(),
            coordinationData: swap.encodeSwapTerms(address(usdc), USDC_AMOUNT, address(weth), WETH_AMOUNT),
            conditionsHash: bytes32(0),
            timestamp: block.timestamp,
            metadata: ""
        });

        IERC8001.AgentIntent memory intent = IERC8001.AgentIntent({
            payloadHash: _hashPayload(payload),
            expiry: uint64(block.timestamp + 1 hours),
            nonce: 1,
            agentId: alice,
            coordinationType: swap.SWAP_TYPE(),
            coordinationValue: 0,
            participants: participants
        });

        // Wrong signature (signed by different key)
        bytes memory badSignature = _signIntentForAddress(intent, alice, 0xBAD);

        vm.expectRevert(abi.encodeWithSelector(IERC8001.ERC8001_BadSignature.selector));
        swap.proposeCoordination(intent, badSignature, payload);
    }

    function test_DuplicateAcceptance_Reverts() public {
        // Propose (alice auto-accepts)
        address[] memory participants = new address[](2);
        participants[0] = bob;
        participants[1] = alice;

        IERC8001.CoordinationPayload memory payload = IERC8001.CoordinationPayload({
            version: keccak256("V1"),
            coordinationType: swap.SWAP_TYPE(),
            coordinationData: swap.encodeSwapTerms(address(usdc), USDC_AMOUNT, address(weth), WETH_AMOUNT),
            conditionsHash: bytes32(0),
            timestamp: block.timestamp,
            metadata: ""
        });

        IERC8001.AgentIntent memory intent = IERC8001.AgentIntent({
            payloadHash: _hashPayload(payload),
            expiry: uint64(block.timestamp + 1 hours),
            nonce: 1,
            agentId: alice,
            coordinationType: swap.SWAP_TYPE(),
            coordinationValue: 0,
            participants: participants
        });

        bytes memory aliceSignature = _signIntent(intent);
        bytes32 intentHash = swap.proposeCoordination(intent, aliceSignature, payload);

        // Try to accept as alice (already auto-accepted)
        IERC8001.AcceptanceAttestation memory acceptance = IERC8001.AcceptanceAttestation({
            intentHash: intentHash,
            participant: alice,
            nonce: 1,
            expiry: uint64(block.timestamp + 1 hours),
            conditionsHash: bytes32(0),
            signature: ""
        });

        bytes memory bobSignature = _signAcceptance(acceptance);
        acceptance.signature = bobSignature;

        // Update to be alice accepting
        acceptance.participant = alice;
        acceptance.signature = _signAcceptanceFor(acceptance, alice, alicePrivateKey);

        vm.expectRevert(abi.encodeWithSelector(IERC8001.ERC8001_DuplicateAcceptance.selector));
        vm.prank(alice);
        swap.acceptCoordination(intentHash, acceptance);
    }

    function test_NonParticipantAcceptance_Reverts() public {
        address[] memory participants = new address[](2);
        participants[0] = bob;
        participants[1] = alice;

        IERC8001.CoordinationPayload memory payload = IERC8001.CoordinationPayload({
            version: keccak256("V1"),
            coordinationType: swap.SWAP_TYPE(),
            coordinationData: swap.encodeSwapTerms(address(usdc), USDC_AMOUNT, address(weth), WETH_AMOUNT),
            conditionsHash: bytes32(0),
            timestamp: block.timestamp,
            metadata: ""
        });

        IERC8001.AgentIntent memory intent = IERC8001.AgentIntent({
            payloadHash: _hashPayload(payload),
            expiry: uint64(block.timestamp + 1 hours),
            nonce: 1,
            agentId: alice,
            coordinationType: swap.SWAP_TYPE(),
            coordinationValue: 0,
            participants: participants
        });

        bytes memory aliceSignature = _signIntent(intent);
        bytes32 intentHash = swap.proposeCoordination(intent, aliceSignature, payload);

        // Try to accept as someone else
        address rando = address(0xBAD);
        IERC8001.AcceptanceAttestation memory acceptance = IERC8001.AcceptanceAttestation({
            intentHash: intentHash,
            participant: rando,
            nonce: 1,
            expiry: uint64(block.timestamp + 1 hours),
            conditionsHash: bytes32(0),
            signature: ""
        });

        acceptance.signature = _signAcceptanceFor(acceptance, rando, 0xBAD);

        vm.expectRevert(abi.encodeWithSelector(IERC8001.ERC8001_NotParticipant.selector));
        vm.prank(rando);
        swap.acceptCoordination(intentHash, acceptance);
    }

    function test_PayloadMismatch_Reverts() public {
        address[] memory participants = new address[](2);
        participants[0] = bob;
        participants[1] = alice;

        IERC8001.CoordinationPayload memory payload = IERC8001.CoordinationPayload({
            version: keccak256("V1"),
            coordinationType: swap.SWAP_TYPE(),
            coordinationData: swap.encodeSwapTerms(address(usdc), USDC_AMOUNT, address(weth), WETH_AMOUNT),
            conditionsHash: bytes32(0),
            timestamp: block.timestamp,
            metadata: ""
        });

        // Intent with wrong hash
        IERC8001.AgentIntent memory intent = IERC8001.AgentIntent({
            payloadHash: keccak256("wrong"),
            expiry: uint64(block.timestamp + 1 hours),
            nonce: 1,
            agentId: alice,
            coordinationType: swap.SWAP_TYPE(),
            coordinationValue: 0,
            participants: participants
        });

        bytes memory aliceSignature = _signIntent(intent);

        vm.expectRevert(abi.encodeWithSelector(IERC8001.ERC8001_PayloadHashMismatch.selector));
        swap.proposeCoordination(intent, aliceSignature, payload);
    }

    function test_NonceTooLow_Reverts() public {
        address[] memory participants = new address[](2);
        participants[0] = bob;
        participants[1] = alice;

        IERC8001.CoordinationPayload memory payload = IERC8001.CoordinationPayload({
            version: keccak256("V1"),
            coordinationType: swap.SWAP_TYPE(),
            coordinationData: swap.encodeSwapTerms(address(usdc), USDC_AMOUNT, address(weth), WETH_AMOUNT),
            conditionsHash: bytes32(0),
            timestamp: block.timestamp,
            metadata: ""
        });

        // First proposal
        IERC8001.AgentIntent memory intent = IERC8001.AgentIntent({
            payloadHash: _hashPayload(payload),
            expiry: uint64(block.timestamp + 1 hours),
            nonce: 1,
            agentId: alice,
            coordinationType: swap.SWAP_TYPE(),
            coordinationValue: 0,
            participants: participants
        });

        bytes memory aliceSignature = _signIntent(intent);
        swap.proposeCoordination(intent, aliceSignature, payload);

        // Second proposal with same nonce
        IERC8001.AgentIntent memory intent2 = IERC8001.AgentIntent({
            payloadHash: _hashPayload(payload),
            expiry: uint64(block.timestamp + 2 hours),
            nonce: 1, // Same nonce - should revert
            agentId: alice,
            coordinationType: swap.SWAP_TYPE(),
            coordinationValue: 0,
            participants: participants
        });

        bytes memory aliceSignature2 = _signIntent(intent2);

        vm.expectRevert(abi.encodeWithSelector(IERC8001.ERC8001_NonceTooLow.selector));
        swap.proposeCoordination(intent2, aliceSignature2, payload);
    }

    function test_AcceptanceExpired_Reverts() public {
        address[] memory participants = new address[](2);
        participants[0] = bob;
        participants[1] = alice;

        IERC8001.CoordinationPayload memory payload = IERC8001.CoordinationPayload({
            version: keccak256("V1"),
            coordinationType: swap.SWAP_TYPE(),
            coordinationData: swap.encodeSwapTerms(address(usdc), USDC_AMOUNT, address(weth), WETH_AMOUNT),
            conditionsHash: bytes32(0),
            timestamp: block.timestamp,
            metadata: ""
        });

        IERC8001.AgentIntent memory intent = IERC8001.AgentIntent({
            payloadHash: _hashPayload(payload),
            expiry: uint64(block.timestamp + 1 hours),
            nonce: 1,
            agentId: alice,
            coordinationType: swap.SWAP_TYPE(),
            coordinationValue: 0,
            participants: participants
        });

        bytes memory aliceSignature = _signIntent(intent);
        bytes32 intentHash = swap.proposeCoordination(intent, aliceSignature, payload);

        // Try to accept with expired acceptance (but intent still valid)
        IERC8001.AcceptanceAttestation memory acceptance = IERC8001.AcceptanceAttestation({
            intentHash: intentHash,
            participant: bob,
            nonce: 1,
            expiry: uint64(block.timestamp - 1), // Already expired
            conditionsHash: bytes32(0),
            signature: ""
        });

        acceptance.signature = _signAcceptance(acceptance);

        vm.expectRevert(abi.encodeWithSelector(IERC8001.ERC8001_ExpiredAcceptance.selector, bob));
        vm.prank(bob);
        swap.acceptCoordination(intentHash, acceptance);
    }

    function test_ExpiredIntent_DynamicStatus() public {
        address[] memory participants = new address[](2);
        participants[0] = bob;
        participants[1] = alice;

        IERC8001.CoordinationPayload memory payload = IERC8001.CoordinationPayload({
            version: keccak256("V1"),
            coordinationType: swap.SWAP_TYPE(),
            coordinationData: swap.encodeSwapTerms(address(usdc), USDC_AMOUNT, address(weth), WETH_AMOUNT),
            conditionsHash: bytes32(0),
            timestamp: block.timestamp,
            metadata: ""
        });

        IERC8001.AgentIntent memory intent = IERC8001.AgentIntent({
            payloadHash: _hashPayload(payload),
            expiry: uint64(block.timestamp + 1 hours),
            nonce: 1,
            agentId: alice,
            coordinationType: swap.SWAP_TYPE(),
            coordinationValue: 0,
            participants: participants
        });

        bytes memory aliceSignature = _signIntent(intent);
        bytes32 intentHash = swap.proposeCoordination(intent, aliceSignature, payload);

        // Move time past expiry
        vm.warp(block.timestamp + 2 hours);

        // Check dynamic status
        (IERC8001.Status status,,,,) = swap.getCoordinationStatus(intentHash);
        assertEq(uint256(status), uint256(IERC8001.Status.Expired), "Should report Expired");
    }

    function test_CancelByNonProposer_BeforeExpiry_Reverts() public {
        address[] memory participants = new address[](2);
        participants[0] = bob;
        participants[1] = alice;

        IERC8001.CoordinationPayload memory payload = IERC8001.CoordinationPayload({
            version: keccak256("V1"),
            coordinationType: swap.SWAP_TYPE(),
            coordinationData: swap.encodeSwapTerms(address(usdc), USDC_AMOUNT, address(weth), WETH_AMOUNT),
            conditionsHash: bytes32(0),
            timestamp: block.timestamp,
            metadata: ""
        });

        IERC8001.AgentIntent memory intent = IERC8001.AgentIntent({
            payloadHash: _hashPayload(payload),
            expiry: uint64(block.timestamp + 1 hours),
            nonce: 1,
            agentId: alice,
            coordinationType: swap.SWAP_TYPE(),
            coordinationValue: 0,
            participants: participants
        });

        bytes memory aliceSignature = _signIntent(intent);
        bytes32 intentHash = swap.proposeCoordination(intent, aliceSignature, payload);

        // Bob tries to cancel before expiry
        vm.expectRevert(abi.encodeWithSelector(IERC8001.ERC8001_NotProposer.selector));
        vm.prank(bob);
        swap.cancelCoordination(intentHash, "Changed my mind");
    }

    function test_CancelByAnyone_AfterExpiry_Succeeds() public {
        address[] memory participants = new address[](2);
        participants[0] = bob;
        participants[1] = alice;

        IERC8001.CoordinationPayload memory payload = IERC8001.CoordinationPayload({
            version: keccak256("V1"),
            coordinationType: swap.SWAP_TYPE(),
            coordinationData: swap.encodeSwapTerms(address(usdc), USDC_AMOUNT, address(weth), WETH_AMOUNT),
            conditionsHash: bytes32(0),
            timestamp: block.timestamp,
            metadata: ""
        });

        IERC8001.AgentIntent memory intent = IERC8001.AgentIntent({
            payloadHash: _hashPayload(payload),
            expiry: uint64(block.timestamp + 1 hours),
            nonce: 1,
            agentId: alice,
            coordinationType: swap.SWAP_TYPE(),
            coordinationValue: 0,
            participants: participants
        });

        bytes memory aliceSignature = _signIntent(intent);
        bytes32 intentHash = swap.proposeCoordination(intent, aliceSignature, payload);

        // Move past expiry
        vm.warp(block.timestamp + 2 hours);

        // Bob can cancel after expiry
        vm.prank(bob);
        swap.cancelCoordination(intentHash, "Expired");

        (IERC8001.Status status,,,,) = swap.getCoordinationStatus(intentHash);
        assertEq(uint256(status), uint256(IERC8001.Status.Cancelled));
    }

    function test_GetRequiredAcceptances() public {
        address[] memory participants = new address[](2);
        participants[0] = bob;
        participants[1] = alice;

        IERC8001.CoordinationPayload memory payload = IERC8001.CoordinationPayload({
            version: keccak256("V1"),
            coordinationType: swap.SWAP_TYPE(),
            coordinationData: swap.encodeSwapTerms(address(usdc), USDC_AMOUNT, address(weth), WETH_AMOUNT),
            conditionsHash: bytes32(0),
            timestamp: block.timestamp,
            metadata: ""
        });

        IERC8001.AgentIntent memory intent = IERC8001.AgentIntent({
            payloadHash: _hashPayload(payload),
            expiry: uint64(block.timestamp + 1 hours),
            nonce: 1,
            agentId: alice,
            coordinationType: swap.SWAP_TYPE(),
            coordinationValue: 0,
            participants: participants
        });

        bytes memory aliceSignature = _signIntent(intent);
        bytes32 intentHash = swap.proposeCoordination(intent, aliceSignature, payload);

        assertEq(swap.getRequiredAcceptances(intentHash), 2, "Should require 2 acceptances");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    function _hashPayload(IERC8001.CoordinationPayload memory payload)
        internal
        pure
        returns (bytes32)
    {
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

    function _hashAttestation(IERC8001.AcceptanceAttestation memory attestation)
        internal
        pure
        returns (bytes32)
    {
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

    function _signIntent(IERC8001.AgentIntent memory intent) internal view returns (bytes memory) {
        bytes32 structHash = _hashIntent(intent);
        bytes32 digest = MessageHashUtils.toTypedDataHash(swap.DOMAIN_SEPARATOR(), structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePrivateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function _signIntentForAddress(
        IERC8001.AgentIntent memory intent,
        address /* signer */,
        uint256 privateKey
    ) internal view returns (bytes memory) {
        bytes32 structHash = _hashIntent(intent);
        bytes32 digest = MessageHashUtils.toTypedDataHash(swap.DOMAIN_SEPARATOR(), structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function _signAcceptance(IERC8001.AcceptanceAttestation memory attestation)
        internal
        view
        returns (bytes memory)
    {
        bytes32 structHash = _hashAttestation(attestation);
        bytes32 digest = MessageHashUtils.toTypedDataHash(swap.DOMAIN_SEPARATOR(), structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(bobPrivateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function _signAcceptanceFor(
        IERC8001.AcceptanceAttestation memory attestation,
        address /* participant */,
        uint256 privateKey
    ) internal view returns (bytes memory) {
        bytes32 structHash = _hashAttestation(attestation);
        bytes32 digest = MessageHashUtils.toTypedDataHash(swap.DOMAIN_SEPARATOR(), structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
