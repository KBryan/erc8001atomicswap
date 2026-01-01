// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";

interface IAtomicSwap {
    struct AgentIntent {
        bytes32 payloadHash;
        uint64 expiry;
        uint64 nonce;
        address agentId;
        bytes32 coordinationType;
        uint256 coordinationValue;
        address[] participants;
    }

    struct CoordinationPayload {
        bytes32 version;
        bytes32 coordinationType;
        address[] participants;
        bytes coordinationData;
    }

    struct AcceptanceAttestation {
        bytes32 intentHash;
        uint64 expiry;
        address agentId;
    }

    function proposeCoordination(
        AgentIntent calldata intent,
        CoordinationPayload calldata payload,
        bytes calldata signature
    ) external returns (bytes32);

    function acceptCoordination(
        bytes32 intentHash,
        AcceptanceAttestation calldata attestation,
        bytes calldata signature
    ) external;

    function executeCoordination(
        bytes32 intentHash,
        CoordinationPayload calldata payload,
        bytes calldata executionData
    ) external;

    function getCoordinationStatus(bytes32 intentHash) external view returns (uint8);
    function getAgentNonce(address agentId) external view returns (uint64);
    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function SWAP_TYPE() external view returns (bytes32);
    function encodeSwapTerms(address, uint256, address, uint256) external pure returns (bytes memory);
}

interface IERC20 {
    function approve(address, uint256) external returns (bool);
    function balanceOf(address) external view returns (uint256);
    function allowance(address, address) external view returns (uint256);
}

// ══════════════════════════════════════════════════════════════════════════════
// CONSTANTS
// ══════════════════════════════════════════════════════════════════════════════

abstract contract SwapConstants {
    address constant ATOMIC_SWAP = 0xD25FaF692736b74A674c8052F904b5C77f9cb2Ed;
    address constant MOCK_USDC = 0x17abd6d0355cB2B933C014133B14245412ca00B6;
    address constant MOCK_WETH = 0xddFaC73904FE867B5526510E695826f4968A2357;

    bytes32 constant INTENT_TYPEHASH = keccak256(
        "AgentIntent(bytes32 payloadHash,uint64 expiry,uint64 nonce,address agentId,bytes32 coordinationType,uint256 coordinationValue,address[] participants)"
    );

    bytes32 constant ACCEPTANCE_TYPEHASH = keccak256(
        "AcceptanceAttestation(bytes32 intentHash,uint64 expiry,address agentId)"
    );
}

// ══════════════════════════════════════════════════════════════════════════════
// STEP 0: APPROVE TOKENS
// ══════════════════════════════════════════════════════════════════════════════
/**
 * Usage:
 *   # AGENT_ONE approves USDC
 *   PRIVATE_KEY=$AGENT_ONE_PK forge script script/SwapScripts.s.sol:ApproveUSDC --rpc-url https://sepolia.base.org --broadcast
 *
 *   # PLAYER_ONE approves WETH  
 *   PRIVATE_KEY=$PLAYER_ONE_PK forge script script/SwapScripts.s.sol:ApproveWETH --rpc-url https://sepolia.base.org --broadcast
 */
contract ApproveUSDC is Script, SwapConstants {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);
        IERC20(MOCK_USDC).approve(ATOMIC_SWAP, type(uint256).max);
        vm.stopBroadcast();
        console2.log("USDC approved for", vm.addr(pk));
    }
}

contract ApproveWETH is Script, SwapConstants {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);
        IERC20(MOCK_WETH).approve(ATOMIC_SWAP, type(uint256).max);
        vm.stopBroadcast();
        console2.log("WETH approved for", vm.addr(pk));
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// STEP 1: PROPOSE SWAP (AGENT_ONE)
// ══════════════════════════════════════════════════════════════════════════════
/**
 * Usage:
 *   PRIVATE_KEY=$AGENT_ONE_PK \
 *   COUNTERPARTY=$PLAYER_ONE \
 *   USDC_AMOUNT=100000000 \
 *   WETH_AMOUNT=100000000000000000 \
 *   forge script script/SwapScripts.s.sol:ProposeSwap --rpc-url https://sepolia.base.org --broadcast -vvvv
 *
 * Defaults: 100 USDC for 0.1 WETH
 */
contract ProposeSwap is Script, SwapConstants {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address counterparty = vm.envAddress("COUNTERPARTY");
        uint256 usdcAmount = vm.envOr("USDC_AMOUNT", uint256(100 * 1e6));
        uint256 wethAmount = vm.envOr("WETH_AMOUNT", uint256(0.1 ether));

        _propose(pk, counterparty, usdcAmount, wethAmount);
    }

    function _propose(uint256 pk, address counterparty, uint256 usdcAmount, uint256 wethAmount) internal {
        address proposer = vm.addr(pk);
        IAtomicSwap swap = IAtomicSwap(ATOMIC_SWAP);

        console2.log("=== PROPOSE SWAP ===");
        console2.log("Proposer:", proposer);
        console2.log("Counterparty:", counterparty);
        console2.log("Offering:", usdcAmount, "USDC (raw)");
        console2.log("Wanting:", wethAmount, "WETH (raw)");

        // Build participants
        address[] memory participants = new address[](2);
        participants[0] = proposer;
        participants[1] = counterparty;

        // Build payload
        bytes32 version = keccak256("V1");
        bytes32 swapType = swap.SWAP_TYPE();
        bytes memory coordData = swap.encodeSwapTerms(MOCK_USDC, usdcAmount, MOCK_WETH, wethAmount);

        IAtomicSwap.CoordinationPayload memory payload = IAtomicSwap.CoordinationPayload({
            version: version,
            coordinationType: swapType,
            participants: participants,
            coordinationData: coordData
        });

        // Compute payload hash
        bytes32 payloadHash = keccak256(abi.encode(
            version,
            swapType,
            keccak256(abi.encodePacked(participants)),
            keccak256(coordData)
        ));

        // Build intent
        uint64 nonce = swap.getAgentNonce(proposer) + 1;
        uint64 expiry = uint64(block.timestamp + 3600);

        IAtomicSwap.AgentIntent memory intent = IAtomicSwap.AgentIntent({
            payloadHash: payloadHash,
            expiry: expiry,
            nonce: nonce,
            agentId: proposer,
            coordinationType: swapType,
            coordinationValue: 0,
            participants: participants
        });

        // Sign
        bytes memory sig = _signIntent(pk, swap.DOMAIN_SEPARATOR(), intent);

        // Submit
        vm.startBroadcast(pk);
        bytes32 intentHash = swap.proposeCoordination(intent, payload, sig);
        vm.stopBroadcast();

        console2.log("");
        console2.log("=== SUCCESS ===");
        console2.log("Intent Hash:", vm.toString(intentHash));
        console2.log("");
        console2.log("Next step - PLAYER_ONE accepts:");
        console2.log("  PRIVATE_KEY=$PLAYER_ONE_PK INTENT_HASH=", vm.toString(intentHash));
    }

    function _signIntent(uint256 pk, bytes32 domain, IAtomicSwap.AgentIntent memory intent) internal pure returns (bytes memory) {
        bytes32 structHash = keccak256(abi.encode(
            INTENT_TYPEHASH,
            intent.payloadHash,
            intent.expiry,
            intent.nonce,
            intent.agentId,
            intent.coordinationType,
            intent.coordinationValue,
            keccak256(abi.encodePacked(intent.participants))
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domain, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// STEP 2: ACCEPT SWAP (PLAYER_ONE)
// ══════════════════════════════════════════════════════════════════════════════
/**
 * Usage:
 *   PRIVATE_KEY=$PLAYER_ONE_PK \
 *   INTENT_HASH=0x... \
 *   forge script script/SwapScripts.s.sol:AcceptSwap --rpc-url https://sepolia.base.org --broadcast -vvvv
 */
contract AcceptSwap is Script, SwapConstants {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        bytes32 intentHash = vm.envBytes32("INTENT_HASH");

        _accept(pk, intentHash);
    }

    function _accept(uint256 pk, bytes32 intentHash) internal {
        address acceptor = vm.addr(pk);
        IAtomicSwap swap = IAtomicSwap(ATOMIC_SWAP);

        console2.log("=== ACCEPT SWAP ===");
        console2.log("Acceptor:", acceptor);
        console2.log("Intent:", vm.toString(intentHash));
        console2.log("Status:", swap.getCoordinationStatus(intentHash));

        // Build attestation
        IAtomicSwap.AcceptanceAttestation memory att = IAtomicSwap.AcceptanceAttestation({
            intentHash: intentHash,
            expiry: uint64(block.timestamp + 3600),
            agentId: acceptor
        });

        // Sign
        bytes memory sig = _signAcceptance(pk, swap.DOMAIN_SEPARATOR(), att);

        // Submit
        vm.startBroadcast(pk);
        swap.acceptCoordination(intentHash, att, sig);
        vm.stopBroadcast();

        console2.log("");
        console2.log("=== SUCCESS ===");
        console2.log("New Status:", swap.getCoordinationStatus(intentHash));
        console2.log("");
        console2.log("Next step - Execute:");
        console2.log("  INTENT_HASH=", vm.toString(intentHash));
    }

    function _signAcceptance(uint256 pk, bytes32 domain, IAtomicSwap.AcceptanceAttestation memory att) internal pure returns (bytes memory) {
        bytes32 structHash = keccak256(abi.encode(
            ACCEPTANCE_TYPEHASH,
            att.intentHash,
            att.expiry,
            att.agentId
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domain, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// STEP 3: EXECUTE SWAP (ANYONE)
// ══════════════════════════════════════════════════════════════════════════════
/**
 * Usage:
 *   PRIVATE_KEY=$AGENT_ONE_PK \
 *   INTENT_HASH=0x... \
 *   PROPOSER=$AGENT_ONE \
 *   COUNTERPARTY=$PLAYER_ONE \
 *   USDC_AMOUNT=100000000 \
 *   WETH_AMOUNT=100000000000000000 \
 *   forge script script/SwapScripts.s.sol:ExecuteSwap --rpc-url https://sepolia.base.org --broadcast -vvvv
 *
 * Note: Must provide original swap terms to reconstruct payload
 */
contract ExecuteSwap is Script, SwapConstants {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        bytes32 intentHash = vm.envBytes32("INTENT_HASH");
        address proposer = vm.envAddress("PROPOSER");
        address counterparty = vm.envAddress("COUNTERPARTY");
        uint256 usdcAmount = vm.envOr("USDC_AMOUNT", uint256(100 * 1e6));
        uint256 wethAmount = vm.envOr("WETH_AMOUNT", uint256(0.1 ether));

        _execute(pk, intentHash, proposer, counterparty, usdcAmount, wethAmount);
    }

    function _execute(
        uint256 pk,
        bytes32 intentHash,
        address proposer,
        address counterparty,
        uint256 usdcAmount,
        uint256 wethAmount
    ) internal {
        IAtomicSwap swap = IAtomicSwap(ATOMIC_SWAP);

        console2.log("=== EXECUTE SWAP ===");
        console2.log("Intent:", vm.toString(intentHash));
        console2.log("Status:", swap.getCoordinationStatus(intentHash));

        // Reconstruct payload
        address[] memory participants = new address[](2);
        participants[0] = proposer;
        participants[1] = counterparty;

        IAtomicSwap.CoordinationPayload memory payload = IAtomicSwap.CoordinationPayload({
            version: keccak256("V1"),
            coordinationType: swap.SWAP_TYPE(),
            participants: participants,
            coordinationData: swap.encodeSwapTerms(MOCK_USDC, usdcAmount, MOCK_WETH, wethAmount)
        });

        // Balances before
        console2.log("");
        console2.log("Balances BEFORE:");
        console2.log("  Proposer USDC:", IERC20(MOCK_USDC).balanceOf(proposer));
        console2.log("  Proposer WETH:", IERC20(MOCK_WETH).balanceOf(proposer));
        console2.log("  Counter USDC:", IERC20(MOCK_USDC).balanceOf(counterparty));
        console2.log("  Counter WETH:", IERC20(MOCK_WETH).balanceOf(counterparty));

        // Execute
        vm.startBroadcast(pk);
        swap.executeCoordination(intentHash, payload, "");
        vm.stopBroadcast();

        console2.log("");
        console2.log("=== SUCCESS ===");
        console2.log("Status:", swap.getCoordinationStatus(intentHash));
        console2.log("");
        console2.log("Balances AFTER:");
        console2.log("  Proposer USDC:", IERC20(MOCK_USDC).balanceOf(proposer));
        console2.log("  Proposer WETH:", IERC20(MOCK_WETH).balanceOf(proposer));
        console2.log("  Counter USDC:", IERC20(MOCK_USDC).balanceOf(counterparty));
        console2.log("  Counter WETH:", IERC20(MOCK_WETH).balanceOf(counterparty));
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// UTILITY: CHECK STATUS
// ══════════════════════════════════════════════════════════════════════════════
/**
 * Usage:
 *   INTENT_HASH=0x... forge script script/SwapScripts.s.sol:CheckStatus --rpc-url https://sepolia.base.org
 */
contract CheckStatus is Script, SwapConstants {
    function run() external view {
        bytes32 intentHash = vm.envBytes32("INTENT_HASH");
        uint8 status = IAtomicSwap(ATOMIC_SWAP).getCoordinationStatus(intentHash);
        string[5] memory names = ["None", "Proposed", "Ready", "Executed", "Cancelled"];
        console2.log("Intent:", vm.toString(intentHash));
        console2.log("Status:", status, "-", names[status]);
    }
}
