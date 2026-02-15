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
    address public USER2 = makeAddr("user2");
    uint256 public constant STARTING_BALANCE = 20 ether;
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;

    event CollateralDeposited(
        address indexed user,
        address indexed tokenCollateralAddress,
        uint256 amountCollateral
    );

    event CollateralRedeemed(
        address indexed redeemedFrom,
        address indexed redeemedTo,
        address indexed tokenCollateralAddress,
        uint256 amountCollateral
    );


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

    //////////////////////////////
    ///// DEPOSIT COLLATERAL /////
    ///////////////////////////////

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

    function testCanDepoistAndGetContractBalance() public {
        uint256 beforeBalance = ERC20Mock(weth).balanceOfInternal(address(dscEngine));

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();

        uint256 afterBalnce = ERC20Mock(weth).balanceOfInternal(address(dscEngine));

        assertEq(afterBalnce , beforeBalance + AMOUNT_COLLATERAL);
    }

    function testDepoitAndEmitEvent() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);

        vm.expectEmit(true, true, true, true);
        emit CollateralDeposited(USER, weth, AMOUNT_COLLATERAL);

        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    //////////////////////
    ///// MINT DSC //////
    ////////////////////

    function testRevertIfMintWithZeroAmount() public{
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__AmountMustBeAboveZero.selector);
        dscEngine.mintDsc(0);
        vm.stopPrank();
    }


    function testRevertIfMintMoreThanAllowed() public depositedCollateral{
         vm.startPrank(USER);
        (,uint256 collateralValueInUsd) = dscEngine.getAccountInformation(USER);
        uint256 maxDscToMint = (collateralValueInUsd * dscEngine.getLiuidationThreshold()) / 100; 
        uint256 amountToMint = maxDscToMint + 1;

        // The contract increments the user's DSC minted before checking health factor,
        // so the revert will contain the health factor computed using `amountToMint`.
        uint256 expectedHealthFactor = (maxDscToMint * 1e18) / amountToMint;
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorTooLow.selector, expectedHealthFactor));
        dscEngine.mintDsc(amountToMint);
        vm.stopPrank();
    }

    function testMintDscAndGetAccountInfo() public depositedCollateral{
        vm.startPrank(USER);
        (,uint256 collateralValueInUsd) = dscEngine.getAccountInformation(USER);
        uint256 maxDscToMint = (collateralValueInUsd * dscEngine.getLiuidationThreshold()) / 100; 
        dscEngine.mintDsc(maxDscToMint);

        (uint256 totalDscMinted, ) = dscEngine.getAccountInformation(USER);
        uint256 expectedTotalDscMinted = maxDscToMint;

        assertEq(totalDscMinted, expectedTotalDscMinted);
        vm.stopPrank();
    }

    function testMintDscAndGetUserTokenBalance() public depositedCollateral{
        vm.startPrank(USER);
        (,uint256 collateralValueInUsd) = dscEngine.getAccountInformation(USER);
        uint256 maxDscToMint = (collateralValueInUsd * dscEngine.getLiuidationThreshold()) / 100; 
        dscEngine.mintDsc(maxDscToMint);

        uint256 userDscBalance = DecentralizedStableCoin(dsc).balanceOf(USER);
        assertEq(userDscBalance, maxDscToMint);
        vm.stopPrank();
    }


    //////////////////////
    ///// BURN DSC //////
    ////////////////////

    function testRevertIfBurnZeroAmount() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__AmountMustBeAboveZero.selector);
        dscEngine.burnDsc(0);
        vm.stopPrank();
    }

    function testRevertIfBurnMoreThanMinted() public depositedCollateral{
        vm.startPrank(USER);
        (,uint256 collateralValueInUsd) = dscEngine.getAccountInformation(USER);
        uint256 maxDscToMint = (collateralValueInUsd * dscEngine.getLiuidationThreshold()) / 100; 
        dscEngine.mintDsc(maxDscToMint);

        uint256 amountToBurn = maxDscToMint + 1;
        vm.expectRevert();
        dscEngine.burnDsc(amountToBurn);
        vm.stopPrank();
    }

    function testBurnDscAndGetAccountInfo() public depositedCollateral{
        vm.startPrank(USER);
        (,uint256 collateralValueInUsd) = dscEngine.getAccountInformation(USER);
        uint256 maxDscToMint = (collateralValueInUsd * dscEngine.getLiuidationThreshold()) / 100; 
        dscEngine.mintDsc(maxDscToMint);

        uint256 amountToBurn = maxDscToMint / 2;

        DecentralizedStableCoin(dsc).approve(address(dscEngine), amountToBurn);
        dscEngine.burnDsc(amountToBurn);

        (uint256 totalDscMintedAfterBurn, ) = dscEngine.getAccountInformation(USER);
        uint256 expectedTotalDscMintedAfterBurn = maxDscToMint - amountToBurn;

        assertEq(totalDscMintedAfterBurn, expectedTotalDscMintedAfterBurn);
        vm.stopPrank();
    }

    function testBurnDscAndGetUserTokenBalance() public depositedCollateral{
        vm.startPrank(USER);
        (,uint256 collateralValueInUsd) = dscEngine.getAccountInformation(USER);
        uint256 maxDscToMint = (collateralValueInUsd * dscEngine.getLiuidationThreshold()) / 100; 
        dscEngine.mintDsc(maxDscToMint);

        uint256 amountToBurn = maxDscToMint / 2;

        DecentralizedStableCoin(dsc).approve(address(dscEngine), amountToBurn);
        dscEngine.burnDsc(amountToBurn);

        uint256 contractDscBalance = DecentralizedStableCoin(dsc).balanceOf(USER);
        assertEq(contractDscBalance, amountToBurn);
        vm.stopPrank();
    }

     //////////////////////////////
    ///// Redeem colatteral //////
   //////////////////////////////

   function testRevertIfRedeemZeroCollateral() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__AmountMustBeAboveZero.selector);
        dscEngine.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRedeemCollateralAndGetAccountInfo() public depositedCollateral{
        vm.startPrank(USER);

        dscEngine.redeemCollateral(weth, AMOUNT_COLLATERAL);

        (,uint256 collateralValueInUsdAfter) = dscEngine.getAccountInformation(USER);

        uint256 expectedCollateralValueAfter = 0;

        assertEq(collateralValueInUsdAfter, expectedCollateralValueAfter);
        vm.stopPrank();
    }

    function testRedeemCollateralAndGetContractBalance() public depositedCollateral{
        uint256 beforeBalance = ERC20Mock(weth).balanceOfInternal(address(dscEngine));

        vm.startPrank(USER);
        dscEngine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();

        uint256 afterBalnce = ERC20Mock(weth).balanceOfInternal(address(dscEngine));

        assertEq(afterBalnce , beforeBalance - AMOUNT_COLLATERAL);
    }

    function testRedeemCollateralAndEmitEvent() public depositedCollateral{
        vm.startPrank(USER);

        vm.expectEmit(true, true, true, true);
        emit CollateralRedeemed(USER, USER, weth, AMOUNT_COLLATERAL);

        dscEngine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testRevertIfRedeemMoreCollateralThanDeposited() public depositedCollateral{
        vm.startPrank(USER);
        uint256 amountToRedeem = AMOUNT_COLLATERAL + 1;
        vm.expectRevert();
        dscEngine.redeemCollateral(weth, amountToRedeem);
        vm.stopPrank();
    }

    function testRevertIfRedeemWithUnapprovedCollateral() public depositedCollateral{
        vm.startPrank(USER);
        ERC20Mock unapprovedToken = new ERC20Mock("unapproved", "UNAPPROVED", USER, AMOUNT_COLLATERAL);
        uint256 amountToRedeem = 1 ether;
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__NotAllowedToken.selector, address(unapprovedToken)));
        dscEngine.redeemCollateral(address(unapprovedToken), amountToRedeem);
        vm.stopPrank(); 
    }

    function testRevertIfRedeemCollateralThatWouldPutHealthFactorTooLow() public depositedCollateral{
        vm.startPrank(USER);
        (,uint256 collateralValueInUsd) = dscEngine.getAccountInformation(USER);
        uint256 maxDscToMint = (collateralValueInUsd * dscEngine.getLiuidationThreshold()) / 100; 
        dscEngine.mintDsc(maxDscToMint);

        uint256 amountToRedeem = AMOUNT_COLLATERAL / 2;

        // DSCEngine decrements the user's collateral before checking health factor.....
       
        uint256 adjustedCollateralAfter = ((collateralValueInUsd - dscEngine.getUsdValue(weth, amountToRedeem)) * dscEngine.getLiuidationThreshold()) / 100;
        uint256 expectedHealthFactor = (adjustedCollateralAfter * 1e18) / maxDscToMint;
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorTooLow.selector, expectedHealthFactor));
        dscEngine.redeemCollateral(weth, amountToRedeem);
        vm.stopPrank();
    }

    function testCanDepositMintRedeemAndBurn() public {
        vm.startPrank(USER);
        // Deposit collateral
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);

        // Mint DSC
        (,uint256 collateralValueInUsd) = dscEngine.getAccountInformation(USER);
        uint256 maxDscToMint = (collateralValueInUsd * dscEngine.getLiuidationThreshold()) / 100; 
        dscEngine.mintDsc(maxDscToMint/2);

        // 

        // Redeem collateral
        uint256 amountToRedeem = AMOUNT_COLLATERAL / 5;
        dscEngine.redeemCollateral(weth, amountToRedeem);

        // Burn DSC
        uint256 amountToBurn = maxDscToMint / 2;
        DecentralizedStableCoin(dsc).approve(address(dscEngine), amountToBurn);
        dscEngine.burnDsc(amountToBurn);

        vm.stopPrank();
    }

     ////////////////////////////
    ///// liquidate user //////
   //////////////////////////

   function testRevertIfLiquidateWithZeroAmount() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__AmountMustBeAboveZero.selector);
        dscEngine.liquidate(USER, weth, 0);
        vm.stopPrank();
    }

    function testRevertIfLiquidateUnapprovedCollateral() public {
        vm.startPrank(USER);
        ERC20Mock unapprovedToken = new ERC20Mock("unapproved", "UNAPPROVED", USER, AMOUNT_COLLATERAL);
        uint256 amountToLiquidate = 1 ether;
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__NotAllowedToken.selector, address(unapprovedToken)));
        dscEngine.liquidate( address(unapprovedToken),USER, amountToLiquidate);
        vm.stopPrank();
    }

}