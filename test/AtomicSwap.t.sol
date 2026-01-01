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
// TEST: THE HELLO WORLD OF ERC-8001
// ═══════════════════════════════════════════════════════════════════════════

/**
 * @title AtomicSwapTest
 * @dev Demonstrates the complete ERC-8001 flow in the simplest possible way.
 *
 * Scenario:
 *   Alice has 100 USDC and wants 0.05 WETH
 *   Bob has 0.05 WETH and wants 100 USDC
 *   They use ERC-8001 to coordinate a trustless swap.
 */
contract AtomicSwapTest is Test {
    AtomicSwap public swap;
    MockUSDC public usdc;
    MockWETH public weth;

    // Alice and Bob
    uint256 alicePrivateKey = 0xA11CE;
    address alice = vm.addr(alicePrivateKey);
    
    uint256 bobPrivateKey = 0xB0B;
    address bob = vm.addr(bobPrivateKey);

    // Swap amounts
    uint256 constant USDC_AMOUNT = 100 * 1e6;      // 100 USDC
    uint256 constant WETH_AMOUNT = 0.05 ether;     // 0.05 WETH

    // EIP-712 constants
    bytes32 constant AGENT_INTENT_TYPEHASH = keccak256(
        "AgentIntent(bytes32 payloadHash,uint64 expiry,uint64 nonce,address agentId,bytes32 coordinationType,uint256 coordinationValue,address[] participants)"
    );
    bytes32 constant ACCEPTANCE_TYPEHASH = keccak256(
        "AcceptanceAttestation(bytes32 intentHash,uint64 expiry,address agentId)"
    );

    function setUp() public {
        // Deploy contracts
        swap = new AtomicSwap();
        usdc = new MockUSDC();
        weth = new MockWETH();

        // Give Alice some USDC
        usdc.mint(alice, USDC_AMOUNT);

        // Give Bob some WETH
        weth.mint(bob, WETH_AMOUNT);

        // Both approve the swap contract
        vm.prank(alice);
        usdc.approve(address(swap), USDC_AMOUNT);

        vm.prank(bob);
        weth.approve(address(swap), WETH_AMOUNT);
    }

    /**
     * @dev THE COMPLETE ERC-8001 FLOW IN ONE TEST
     *
     * This is the "Hello World" - the simplest demonstration of:
     * 1. Propose: Alice creates and signs an intent
     * 2. Accept: Bob reviews and signs an acceptance
     * 3. Execute: Swap happens atomically
     */
    function test_HelloWorld_AtomicSwap() public {
        // ═══════════════════════════════════════════════════════════════════
        // STEP 1: ALICE PROPOSES THE SWAP
        // ═══════════════════════════════════════════════════════════════════
        
        // Define the swap terms
        bytes memory coordinationData = swap.encodeSwapTerms(
            address(usdc),   // Alice offers USDC
            USDC_AMOUNT,     // 100 USDC
            address(weth),   // Alice wants WETH
            WETH_AMOUNT      // 0.05 WETH
        );

        // Define participants (Alice proposes, Bob must accept)
        address[] memory participants = new address[](2);
        participants[0] = alice;
        participants[1] = bob;

        // Create the coordination payload
        IERC8001.CoordinationPayload memory payload = IERC8001.CoordinationPayload({
            version: keccak256("V1"),
            coordinationType: swap.SWAP_TYPE(),
            participants: participants,
            coordinationData: coordinationData
        });

        // Create the intent
        IERC8001.AgentIntent memory intent = IERC8001.AgentIntent({
            payloadHash: _hashPayload(payload),
            expiry: uint64(block.timestamp + 1 hours),
            nonce: 1,
            agentId: alice,
            coordinationType: swap.SWAP_TYPE(),
            coordinationValue: 0,
            participants: participants
        });

        // Alice signs the intent
        bytes memory aliceSignature = _signIntent(intent, alicePrivateKey);

        // Submit the proposal
        bytes32 intentHash = swap.proposeCoordination(intent, payload, aliceSignature);

        console2.log("Step 1: Alice proposed swap");
        console2.log("  Intent hash:", vm.toString(intentHash));
        assertEq(uint256(swap.getCoordinationStatus(intentHash)), uint256(IERC8001.Status.Proposed));

        // ═══════════════════════════════════════════════════════════════════
        // STEP 2: BOB ACCEPTS THE SWAP
        // ═══════════════════════════════════════════════════════════════════

        // Bob creates an acceptance attestation
        IERC8001.AcceptanceAttestation memory acceptance = IERC8001.AcceptanceAttestation({
            intentHash: intentHash,
            expiry: uint64(block.timestamp + 1 hours),
            agentId: bob
        });

        // Bob signs the acceptance
        bytes memory bobSignature = _signAcceptance(acceptance, bobPrivateKey);

        // Submit the acceptance
        swap.acceptCoordination(intentHash, acceptance, bobSignature);

        console2.log("Step 2: Bob accepted swap");
        assertEq(uint256(swap.getCoordinationStatus(intentHash)), uint256(IERC8001.Status.Ready));

        // ═══════════════════════════════════════════════════════════════════
        // STEP 3: EXECUTE THE SWAP
        // ═══════════════════════════════════════════════════════════════════

        // Check balances before
        uint256 aliceUsdcBefore = usdc.balanceOf(alice);
        uint256 aliceWethBefore = weth.balanceOf(alice);
        uint256 bobUsdcBefore = usdc.balanceOf(bob);
        uint256 bobWethBefore = weth.balanceOf(bob);

        // Anyone can execute once both parties have signed
        swap.executeCoordination(intentHash, payload, "");

        console2.log("Step 3: Swap executed!");
        assertEq(uint256(swap.getCoordinationStatus(intentHash)), uint256(IERC8001.Status.Executed));

        // ═══════════════════════════════════════════════════════════════════
        // VERIFY: TOKENS SWAPPED CORRECTLY
        // ═══════════════════════════════════════════════════════════════════

        // Alice gave USDC, received WETH
        assertEq(usdc.balanceOf(alice), aliceUsdcBefore - USDC_AMOUNT);
        assertEq(weth.balanceOf(alice), aliceWethBefore + WETH_AMOUNT);

        // Bob gave WETH, received USDC
        assertEq(weth.balanceOf(bob), bobWethBefore - WETH_AMOUNT);
        assertEq(usdc.balanceOf(bob), bobUsdcBefore + USDC_AMOUNT);

        console2.log("");
        console2.log("=== SWAP COMPLETE ===");
        console2.log("Alice: -100 USDC, +0.05 WETH");
        console2.log("Bob:   +100 USDC, -0.05 WETH");
    }

    /**
     * @dev Demonstrates what happens if Bob doesn't accept
     */
    function test_NoAcceptance_NothingHappens() public {
        address[] memory participants = new address[](2);
        participants[0] = alice;
        participants[1] = bob;

        bytes memory coordinationData = swap.encodeSwapTerms(
            address(usdc), USDC_AMOUNT, address(weth), WETH_AMOUNT
        );

        IERC8001.CoordinationPayload memory payload = IERC8001.CoordinationPayload({
            version: keccak256("V1"),
            coordinationType: swap.SWAP_TYPE(),
            participants: participants,
            coordinationData: coordinationData
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

        bytes memory signature = _signIntent(intent, alicePrivateKey);
        bytes32 intentHash = swap.proposeCoordination(intent, payload, signature);

        // Bob never accepts - try to execute anyway
        vm.expectRevert(abi.encodeWithSelector(
            IERC8001.NotReady.selector,
            intentHash,
            IERC8001.Status.Proposed
        ));
        swap.executeCoordination(intentHash, payload, "");

        // Balances unchanged
        assertEq(usdc.balanceOf(alice), USDC_AMOUNT);
        assertEq(weth.balanceOf(bob), WETH_AMOUNT);

        console2.log("Without Bob's acceptance, nothing happens.");
        console2.log("Alice still has her USDC, Bob still has his WETH.");
    }

    /**
     * @dev Demonstrates cancellation
     */
    function test_AliceCanCancel() public {
        address[] memory participants = new address[](2);
        participants[0] = alice;
        participants[1] = bob;

        bytes memory coordinationData = swap.encodeSwapTerms(
            address(usdc), USDC_AMOUNT, address(weth), WETH_AMOUNT
        );

        IERC8001.CoordinationPayload memory payload = IERC8001.CoordinationPayload({
            version: keccak256("V1"),
            coordinationType: swap.SWAP_TYPE(),
            participants: participants,
            coordinationData: coordinationData
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

        bytes memory signature = _signIntent(intent, alicePrivateKey);
        bytes32 intentHash = swap.proposeCoordination(intent, payload, signature);

        // Alice changes her mind
        vm.prank(alice);
        swap.cancelCoordination(intentHash);

        assertEq(uint256(swap.getCoordinationStatus(intentHash)), uint256(IERC8001.Status.Cancelled));
        console2.log("Alice cancelled. Swap will never execute.");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    function _hashPayload(IERC8001.CoordinationPayload memory payload) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            payload.version,
            payload.coordinationType,
            keccak256(abi.encodePacked(payload.participants)),
            keccak256(payload.coordinationData)
        ));
    }

    function _hashIntent(IERC8001.AgentIntent memory intent) internal pure returns (bytes32) {
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

    function _signIntent(
        IERC8001.AgentIntent memory intent,
        uint256 privateKey
    ) internal view returns (bytes memory) {
        bytes32 structHash = _hashIntent(intent);
        bytes32 digest = MessageHashUtils.toTypedDataHash(swap.DOMAIN_SEPARATOR(), structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function _signAcceptance(
        IERC8001.AcceptanceAttestation memory attestation,
        uint256 privateKey
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(abi.encode(
            ACCEPTANCE_TYPEHASH,
            attestation.intentHash,
            attestation.expiry,
            attestation.agentId
        ));
        bytes32 digest = MessageHashUtils.toTypedDataHash(swap.DOMAIN_SEPARATOR(), structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
