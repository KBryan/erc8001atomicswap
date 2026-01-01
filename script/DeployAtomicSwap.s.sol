// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {AtomicSwap} from "../src/contracts/examples/AtomicSwap.sol";

/**
 * @title DeployAtomicSwap
 * @dev Deployment script for AtomicSwap on Base Sepolia
 *
 * Usage:
 *   # Set your private key
 *   export PRIVATE_KEY=0x...
 *
 *   # Deploy to Base Sepolia
 *   forge script script/DeployAtomicSwap.s.sol:DeployAtomicSwap \
 *     --rpc-url https://sepolia.base.org \
 *     --broadcast \
 *     --verify \
 *     --etherscan-api-key $BASESCAN_API_KEY
 *
 *   # Or with a local .env file
 *   source .env && forge script script/DeployAtomicSwap.s.sol:DeployAtomicSwap \
 *     --rpc-url $BASE_SEPOLIA_RPC \
 *     --broadcast \
 *     --verify
 */
contract DeployAtomicSwap is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("==============================================");
        console2.log("Deploying AtomicSwap to Base Sepolia");
        console2.log("==============================================");
        console2.log("Deployer:", deployer);
        console2.log("Balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        AtomicSwap swap = new AtomicSwap();

        vm.stopBroadcast();

        console2.log("==============================================");
        console2.log("Deployment Complete!");
        console2.log("==============================================");
        console2.log("AtomicSwap:", address(swap));
        console2.log("DOMAIN_SEPARATOR:", vm.toString(swap.DOMAIN_SEPARATOR()));
        console2.log("SWAP_TYPE:", vm.toString(swap.SWAP_TYPE()));
        console2.log("");
        console2.log("Verify with:");
        console2.log("  forge verify-contract", address(swap), "AtomicSwap --chain base-sepolia");
    }
}

/**
 * @title DeployAtomicSwapWithMocks
 * @dev Deploys AtomicSwap along with mock tokens for testing
 */
contract DeployAtomicSwapWithMocks is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("==============================================");
        console2.log("Deploying AtomicSwap + Mock Tokens");
        console2.log("==============================================");
        console2.log("Deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy mock tokens
        MockERC20 mockUSDC = new MockERC20("Mock USDC", "mUSDC", 6);
        MockERC20 mockWETH = new MockERC20("Mock WETH", "mWETH", 18);

        // Deploy swap contract
        AtomicSwap swap = new AtomicSwap();

        // Mint some tokens to deployer for testing
        mockUSDC.mint(deployer, 10_000 * 1e6);   // 10,000 USDC
        mockWETH.mint(deployer, 10 * 1e18);      // 10 WETH

        vm.stopBroadcast();

        console2.log("==============================================");
        console2.log("Deployment Complete!");
        console2.log("==============================================");
        console2.log("AtomicSwap:", address(swap));
        console2.log("Mock USDC:", address(mockUSDC));
        console2.log("Mock WETH:", address(mockWETH));
        console2.log("");
        console2.log("Deployer balances:");
        console2.log("  mUSDC:", mockUSDC.balanceOf(deployer) / 1e6);
        console2.log("  mWETH:", mockWETH.balanceOf(deployer) / 1e18);
    }
}

/**
 * @dev Simple mock ERC20 for testing
 */
contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;
    
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}
