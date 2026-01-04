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
 * @dev Deploys AtomicSwap along with mock tokens for testing.
 *      Funds AGENT_ONE and PLAYER_ONE with tokens for swap testing.
 *
 * Required environment variables:
 *   PRIVATE_KEY  - Deployer private key
 *   AGENT_ONE    - Address of first test account (will receive USDC)
 *   PLAYER_ONE   - Address of second test account (will receive WETH)
 */
contract DeployAtomicSwapWithMocks is Script {
    // Token amounts for testing
    uint256 constant USDC_AMOUNT = 1_000 * 1e6; // 1,000 USDC
    uint256 constant WETH_AMOUNT = 1 * 1e18; // 1 WETH

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Load test accounts from environment
        address agentOne = vm.envAddress("AGENT_ONE");
        address playerOne = vm.envAddress("PLAYER_ONE");

        console2.log("==============================================");
        console2.log("Deploying AtomicSwap + Mock Tokens");
        console2.log("==============================================");
        console2.log("Deployer:", deployer);
        console2.log("AGENT_ONE:", agentOne);
        console2.log("PLAYER_ONE:", playerOne);
        console2.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy mock tokens
        MockERC20 mockUSDC = new MockERC20("Mock USDC", "mUSDC", 6);
        MockERC20 mockWETH = new MockERC20("Mock WETH", "mWETH", 18);

        // Deploy swap contract
        AtomicSwap swap = new AtomicSwap();

        // ══════════════════════════════════════════════════════════════════
        // FUND TEST ACCOUNTS
        // ══════════════════════════════════════════════════════════════════

        // AGENT_ONE gets USDC (will offer USDC in swaps)
        mockUSDC.mint(agentOne, USDC_AMOUNT);

        // PLAYER_ONE gets WETH (will offer WETH in swaps)
        mockWETH.mint(playerOne, WETH_AMOUNT);

        // Also give deployer some of each for flexibility
        mockUSDC.mint(deployer, USDC_AMOUNT);
        mockWETH.mint(deployer, WETH_AMOUNT);

        vm.stopBroadcast();

        // ══════════════════════════════════════════════════════════════════
        // OUTPUT SUMMARY
        // ══════════════════════════════════════════════════════════════════

        console2.log("==============================================");
        console2.log("Deployment Complete!");
        console2.log("==============================================");
        console2.log("");
        console2.log("Contracts:");
        console2.log("  AtomicSwap:", address(swap));
        console2.log("  Mock USDC:", address(mockUSDC));
        console2.log("  Mock WETH:", address(mockWETH));
        console2.log("");
        console2.log("AGENT_ONE balances:");
        console2.log("  mUSDC:", mockUSDC.balanceOf(agentOne));
        console2.log("  mWETH:", mockWETH.balanceOf(agentOne));
        console2.log("");
        console2.log("PLAYER_ONE balances:");
        console2.log("  mUSDC:", mockUSDC.balanceOf(playerOne));
        console2.log("  mWETH:", mockWETH.balanceOf(playerOne));
        console2.log("");
        console2.log("==============================================");
        console2.log("FRONTEND CONFIG (copy these):");
        console2.log("==============================================");
        console2.log("");
        console2.log("const ATOMIC_SWAP = '", address(swap), "';");
        console2.log("const MOCK_USDC = '", address(mockUSDC), "';");
        console2.log("const MOCK_WETH = '", address(mockWETH), "';");
        console2.log("");
        console2.log("==============================================");
        console2.log("NEXT STEPS:");
        console2.log("==============================================");
        console2.log("1. AGENT_ONE must approve AtomicSwap for USDC:");
        console2.log("   mockUSDC.approve(", address(swap), ", amount)");
        console2.log("");
        console2.log("2. PLAYER_ONE must approve AtomicSwap for WETH:");
        console2.log("   mockWETH.approve(", address(swap), ", amount)");
        console2.log("");
        console2.log("3. Test a swap:");
        console2.log("   - AGENT_ONE proposes: 100 USDC for 0.1 WETH");
        console2.log("   - PLAYER_ONE accepts");
        console2.log("   - Anyone executes");
    }
}

/**
 * @title DeployMockTokensOnly
 * @dev Deploys mock tokens and funds test accounts.
 *      Use this when AtomicSwap is already deployed.
 *
 * Usage:
 *   ATOMIC_SWAP=0xD25FaF692736b74A674c8052F904b5C77f9cb2Ed \
 *   forge script script/DeployAtomicSwap.s.sol:DeployMockTokensOnly \
 *     --rpc-url base_sepolia --broadcast -vvvv
 *
 * Required environment variables:
 *   PRIVATE_KEY  - Deployer private key
 *   AGENT_ONE    - Address of first test account (will receive USDC)
 *   PLAYER_ONE   - Address of second test account (will receive WETH)
 *   ATOMIC_SWAP  - Address of already-deployed AtomicSwap contract
 */
contract DeployMockTokensOnly is Script {
    uint256 constant USDC_AMOUNT = 1_000 * 1e6;
    uint256 constant WETH_AMOUNT = 1 * 1e18;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address agentOne = vm.envAddress("AGENT_ONE");
        address playerOne = vm.envAddress("PLAYER_ONE");
        address atomicSwap = vm.envAddress("ATOMIC_SWAP");

        console2.log("==============================================");
        console2.log("Deploying Mock Tokens Only");
        console2.log("==============================================");
        console2.log("Deployer:", deployer);
        console2.log("AGENT_ONE:", agentOne);
        console2.log("PLAYER_ONE:", playerOne);
        console2.log("AtomicSwap:", atomicSwap);
        console2.log("");

        vm.startBroadcast(deployerPrivateKey);

        MockERC20 mockUSDC = new MockERC20("Mock USDC", "mUSDC", 6);
        MockERC20 mockWETH = new MockERC20("Mock WETH", "mWETH", 18);

        // Fund accounts
        mockUSDC.mint(agentOne, USDC_AMOUNT);
        mockWETH.mint(playerOne, WETH_AMOUNT);
        mockUSDC.mint(deployer, USDC_AMOUNT);
        mockWETH.mint(deployer, WETH_AMOUNT);

        vm.stopBroadcast();

        console2.log("==============================================");
        console2.log("Deployment Complete!");
        console2.log("==============================================");
        console2.log("");
        console2.log("FRONTEND CONFIG (copy-paste ready):");
        console2.log("==============================================");
        console2.log("");
        console2.log("const ATOMIC_SWAP =", atomicSwap);
        console2.log("const MOCK_USDC =", address(mockUSDC));
        console2.log("const MOCK_WETH =", address(mockWETH));
        console2.log("");
        console2.log("AGENT_ONE:", agentOne);
        console2.log("  mUSDC balance:", USDC_AMOUNT);
        console2.log("");
        console2.log("PLAYER_ONE:", playerOne);
        console2.log("  mWETH balance:", WETH_AMOUNT);
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
