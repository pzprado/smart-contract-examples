// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TransferUSDC} from "../src/TransferUSDC.sol";
import {CrossChainReceiver} from "../src/CrossChainReceiver.sol";
import {SwapTestnetUSDC} from "../src/SwapTestnetUSDC.sol";
import {TransferUSDCScript} from "../script/TransferUSDC.s.sol";
import {DeployReceiverAndSwapScript} from "../script/DeployReceiverAndSwap.s.sol";
import {EncodeExtraArgs} from "./utils/EncodeExtraArgs.sol";
import {TransferHelperConfig} from "../script/TransferHelperConfig.s.sol";
import {SwapHelperConfig} from "../script/SwapHelperConfig.s.sol";
import {ReceiverHelperConfig} from "../script/ReceiverHelperConfig.s.sol";

contract CrossChainTransferUsdcTest is Test {
    CCIPLocalSimulatorFork public ccipLocalSimulatorFork;
    uint256 public sepoliaFork;
    uint256 public fujiFork;
    Register.NetworkDetails public sepoliaNetworkDetails;
    Register.NetworkDetails public fujiNetworkDetails;

    TransferUSDC public fujiTransfer;
    CrossChainReceiver public sepoliaReceiver;
    SwapTestnetUSDC public sepoliaSwap;

    address public fujiRouter;
    address public fujiLink;
    address public fujiUsdc;
    uint256 private deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    address private USER = vm.addr(deployerPrivateKey);
    address public sepoliaUsdc;

    function setUp() public {
        // Initialize Forks
        sepoliaFork = vm.createFork(vm.envString("SEPOLIA_RPC_URL"));
        fujiFork = vm.createSelectFork(vm.envString("FUJI_RPC_URL"));

        // Initialize CCIP Simulator
        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));

        // Deploy contracts on Fuji
        vm.selectFork(fujiFork);
        fujiNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        require(fujiNetworkDetails.chainSelector == 14767482510784806043, "Invalid chain selector for Fuji");

        TransferHelperConfig transferHelperConfig = new TransferHelperConfig();
        (fujiRouter, fujiLink, fujiUsdc) = transferHelperConfig.activeNetworkConfig();

        vm.prank(USER);
        fujiTransfer = new TransferUSDC(fujiRouter, fujiLink, fujiUsdc);

        // Deploy contracts on Sepolia
        vm.selectFork(sepoliaFork);
        sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        require(sepoliaNetworkDetails.chainSelector == 16015286601757825753, "Invalid chain selector for Sepolia");

        ReceiverHelperConfig receiverHelperConfig = new ReceiverHelperConfig();
        (address router, address comet) = receiverHelperConfig.activeNetworkConfig();

        SwapHelperConfig swapHelperConfig = new SwapHelperConfig();
        address compoundUsdcToken;
        address fauceteer;
        (sepoliaUsdc, compoundUsdcToken, fauceteer) = swapHelperConfig.activeNetworkConfig();

        vm.startPrank(USER);
        sepoliaSwap = new SwapTestnetUSDC(sepoliaUsdc, compoundUsdcToken, fauceteer);
        sepoliaReceiver = new CrossChainReceiver(router, comet, address(sepoliaSwap));
        vm.stopPrank();

        // Allowlist settings
        vm.selectFork(fujiFork);
        vm.prank(USER);
        fujiTransfer.allowlistDestinationChain(sepoliaNetworkDetails.chainSelector, true);
        ccipLocalSimulatorFork.requestLinkFromFaucet(address(fujiTransfer), 3 ether);

        vm.prank(USER);
        IERC20(fujiUsdc).approve(address(fujiTransfer), 1_000_000);

        vm.selectFork(sepoliaFork);
        vm.prank(USER);
        sepoliaReceiver.allowlistSourceChain(fujiNetworkDetails.chainSelector, true);
    }

    function testTransferUSDC() public {
        vm.selectFork(fujiFork);
        vm.prank(USER);
        fujiTransfer.transferUsdc(sepoliaNetworkDetails.chainSelector, address(sepoliaReceiver), 1_000_000, 0);

        ccipLocalSimulatorFork.switchChainAndRouteMessage(sepoliaFork);
        assertEq(IERC20(sepoliaUsdc).balanceOf(address(sepoliaReceiver)), 1_000_000);
    }
}
