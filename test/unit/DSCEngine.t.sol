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
    address btcUsdPriceFeed;
    address weth;

    address public USER = makeAddr("user");
    uint256 public constant STARTING_BALANCE = 20 ether;
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;


    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dscEngine,config) = deployer.run();
        (ethUsdPriceFeed,btcUsdPriceFeed , weth, , ) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_BALANCE);
    }

    address[] public tokensAddresses;
    address[] public priceFeedAddresses;


    function testRevertIfTokenLengthDoesNotMatchPriceFeedLength() public {
        tokensAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed); // Add an extra price feed to cause

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokensAddresses, priceFeedAddresses,address(dsc));
    }

    function testGetUsdValue() public {
        uint256 ethAmount = 15e18; // 15 ETH
        uint256 expectedUsdValue = 30000e18; // 15 ETH * $2000/ETH = $30,000 (with 8 decimals)
        uint256 actualUsdValue = dscEngine.getUsdValue(weth, ethAmount);


        assertEq(actualUsdValue, expectedUsdValue);
    }

    function testGetTokenAmountFromUsdValue() public {
       uint256 usdAmount = 30000e18; // $30,000
        uint256 expectedEthAmount = 15e18; // $30,000 / $2000/ETH = 15 ETH (with 8 decimals)
        uint256 actualEthAmount = dscEngine.getTokenAmountFromUsdValue(weth, usdAmount);

        assertEq(actualEthAmount, expectedEthAmount);
    }

    function testRevertIfDepositZeroCollateral() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__AmountMustBeAboveZero.selector);
        dscEngine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertUnapprovedCollateral() public {
        vm.startPrank(USER);
        ERC20Mock unapprovedToken = new ERC20Mock("unapproved", "UNAPPROVED", USER, AMOUNT_COLLATERAL);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__NotAllowedToken.selector, address(unapprovedToken)));
        dscEngine.depositCollateral(address(unapprovedToken), 1 ether);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral{


        (uint256 totalDscMinted,uint256 collateralValueInUsd) = dscEngine.getAccountInformation(USER);

        uint256 expectedDepoistAmount = dscEngine.getTokenAmountFromUsdValue(weth, collateralValueInUsd);
        uint256 expectedTotalDscMinted = 0;

        assertEq(AMOUNT_COLLATERAL, expectedDepoistAmount);
        assertEq(totalDscMinted, expectedTotalDscMinted);

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