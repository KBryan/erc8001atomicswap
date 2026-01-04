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

    bytes32 constant ACCEPTANCE_TYPEHASH =
        keccak256("AcceptanceAttestation(bytes32 intentHash,uint64 expiry,address agentId)");

    function run() public {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        bytes32 intentHash = vm.envBytes32("INTENT_HASH");

        _run(pk, intentHash);
    }

    function _run(uint256 pk, bytes32 intentHash) internal {
        address signer = vm.addr(pk);
        IAtomicSwap swap = IAtomicSwap(ATOMIC_SWAP);

        console2.log("Signer:", signer);
        console2.log("Intent:", vm.toString(intentHash));
        console2.log("Status:", swap.getCoordinationStatus(intentHash));

        // Build attestation
        IAtomicSwap.AcceptanceAttestation memory att = IAtomicSwap.AcceptanceAttestation({
            intentHash: intentHash, expiry: uint64(block.timestamp + 3600), agentId: signer
        });

        // Sign
        bytes memory sig = _sign(pk, swap.DOMAIN_SEPARATOR(), att);

        // Submit
        vm.startBroadcast(pk);
        swap.acceptCoordination(intentHash, att, sig);
        vm.stopBroadcast();

        console2.log("New Status:", swap.getCoordinationStatus(intentHash));
    }

    function _sign(
        uint256 pk,
        bytes32 domainSeparator,
        IAtomicSwap.AcceptanceAttestation memory att
    ) internal pure returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(ACCEPTANCE_TYPEHASH, att.intentHash, att.expiry, att.agentId)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }
}
