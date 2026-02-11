// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test,console} from 'forge-std/Test.sol';
import {DeployDSC} from '../../script/DeployDSC.s.sol';
import {DSCEngine} from '../../src/DSCEngine.sol';
import {DecentralizedStableCoin} from '../../src/DecentralizedStableCoin.sol';
import {HelperConfig} from '../../script/HelperConfig.s.sol';
import {ERC20Mock} from '../mocks/ERC20Mock.sol';

contract DSCEngineTest is Test {
    DSCEngine public dscEngine;
    DecentralizedStableCoin public dsc;
    DeployDSC public deployer;
    HelperConfig public config;
    address ethUsdPriceFeed;
    address weth;

    address public USER = makeAddr("user");
    uint256 public constant STARTING_BALANCE = 20 ether;
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;


    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dscEngine,config) = deployer.run();
        (ethUsdPriceFeed, , weth, , ) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_BALANCE);
    }

    function testGetUsdValue() public {
        uint256 ethAmount = 15e18; // 15 ETH
        uint256 expectedUsdValue = 30000e18; // 15 ETH * $2000/ETH = $30,000 (with 8 decimals)
        uint256 actualUsdValue = dscEngine.getUsdValue(weth, ethAmount);


        assertEq(actualUsdValue, expectedUsdValue);
    }

    function testRevertIfDepositZeroCollateral() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__AmountMustBeAboveZero.selector);
        dscEngine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    // function testDepositCollateral() public {
    //     uint256 collateralAmount = 1e18; // 1 ETH
    //     // Give the test contract some WETH to work with
    //     deal(weth, address(this), collateralAmount);
    //     IERC20(weth).approve(address(dscEngine), collateralAmount);

    //     dscEngine.depositCollateral(weth, collateralAmount);

    //     uint256 depositedCollateral = dscEngine.getCollateralBalance(address(this), weth);
    //     assertEq(depositedCollateral, collateralAmount);
    // }
}