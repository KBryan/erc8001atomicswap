// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";

interface IAtomicSwap {
    struct AcceptanceAttestation {
        bytes32 intentHash;
        uint64 expiry;
        address agentId;
    }

    function acceptCoordination(
        bytes32 intentHash,
        AcceptanceAttestation calldata attestation,
        bytes calldata signature
    ) external;

    function getCoordinationStatus(bytes32 intentHash) external view returns (uint8);
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

/**
 * @title AcceptSwap
 * @dev Accept an AtomicSwap proposal
 *
 * Usage:
 *   INTENT_HASH=0xb704ef0989d36769d1042763b849b8844e1d28a7391adfcf904377efe3f7923a \
 *   forge script script/AcceptSwap.s.sol:AcceptSwap \
 *     --rpc-url https://sepolia.base.org \
 *     --broadcast \
 *     -vvvv
 */
contract AcceptSwap is Script {
    address constant ATOMIC_SWAP = 0xD25FaF692736b74A674c8052F904b5C77f9cb2Ed;

    // EIP-712 typehash for AcceptanceAttestation
    bytes32 constant ACCEPTANCE_TYPEHASH = keccak256(
        "AcceptanceAttestation(bytes32 intentHash,uint64 expiry,address agentId)"
    );

    function run() public {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        bytes32 intentHash = vm.envBytes32("INTENT_HASH");
        
        address signer = vm.addr(pk);
        IAtomicSwap swap = IAtomicSwap(ATOMIC_SWAP);

        console2.log("==============================================");
        console2.log("Accepting Swap");
        console2.log("==============================================");
        console2.log("Signer:", signer);
        console2.log("Intent Hash:", vm.toString(intentHash));

        // Check status
        uint8 status = swap.getCoordinationStatus(intentHash);
        string[5] memory statusNames = ["None", "Proposed", "Ready", "Executed", "Cancelled"];
        console2.log("Current Status:", statusNames[status]);

        require(status == 1, "Intent not in Proposed status");

        // Build attestation
        uint64 expiry = uint64(block.timestamp + 3600);
        IAtomicSwap.AcceptanceAttestation memory attestation = IAtomicSwap.AcceptanceAttestation({
            intentHash: intentHash,
            expiry: expiry,
            agentId: signer
        });

        // Compute EIP-712 digest
        bytes32 domainSeparator = swap.DOMAIN_SEPARATOR();
        bytes32 structHash = keccak256(abi.encode(
            ACCEPTANCE_TYPEHASH,
            attestation.intentHash,
            attestation.expiry,
            attestation.agentId
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        // Sign
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        console2.log("Signature obtained");

        // Submit
        vm.startBroadcast(pk);
        swap.acceptCoordination(intentHash, attestation, signature);
        vm.stopBroadcast();

        // Check new status
        uint8 newStatus = swap.getCoordinationStatus(intentHash);
        console2.log("==============================================");
        console2.log("New Status:", statusNames[newStatus]);
        console2.log("==============================================");
    }
}
