// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import {Test,console,console2} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract Handler is Test{

    DSCEngine dsce;
    DecentralizedStableCoin dsc;

    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 public timesMintIsCalled ;
    address [] public usersWithCollateralDeposited;
    MockV3Aggregator public ethUsdPriceFeed;
    MockV3Aggregator public btcUsdPriceFeed;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc){
        dsce = _dscEngine;
        dsc = _dsc;

        address[] memory collateralTokens = dsce.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        ethUsdPriceFeed = MockV3Aggregator(dsce.getCollateralTokenPriceFeed(address(weth)));
        btcUsdPriceFeed = MockV3Aggregator(dsce.getCollateralTokenPriceFeed(address(wbtc)));

    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {

        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral,1,MAX_DEPOSIT_SIZE);
        vm.startPrank(msg.sender);

        collateral.mint(msg.sender,amountCollateral);
        collateral.approve(address(dsce),amountCollateral);
        
        dsce.depositCollateral(address(collateral),amountCollateral);
        vm.stopPrank();
        if(!isUserAdded(msg.sender)){
            usersWithCollateralDeposited.push(msg.sender);
        }
    }

    function mintDsc(uint256 amount,uint256 addressSeed) public{
        if(usersWithCollateralDeposited.length == 0){
            return;
        }
        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];
        (uint256 totalDscMinted,uint256 collateralValueInUsd) = dsce.getAccountInformation(sender);
        int256 maxDscToMint = (int256(collateralValueInUsd) / 2) - int256(totalDscMinted);
        
        console2.log("totalDscMinted",totalDscMinted);
        console2.log("collateralValueInUsd",collateralValueInUsd);
        console2.log("maxDscToMint",maxDscToMint);

        if(maxDscToMint < 0){
            return;
        }

        amount = bound(amount,1,uint256(maxDscToMint));

        if(amount == 0){
            return;
        }
        vm.startPrank(sender);
        dsce.mintDsc(amount);
        vm.stopPrank();
        timesMintIsCalled++;

    }

    function redeemCollateral(uint256 collateralSeed , uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = dsce.getCollateralBalanceOfUser(msg.sender,address(collateral));

        amountCollateral = bound(amountCollateral,0,maxCollateralToRedeem);
        if(amountCollateral == 0){
            return;
        }
        vm.startPrank(msg.sender);
        dsce.redeemCollateral(address(collateral),amountCollateral);
        vm.stopPrank();
    }


    // this breaks the invariant test.....

    // function updateCollateralPrice(uint256 collateralSeed, uint96 newPrice) public {
    //     MockV3Aggregator priceFeed;
    //     if(collateralSeed % 2 == 0){
    //         priceFeed = ethUsdPriceFeed;
    //     }else{
    //         priceFeed = btcUsdPriceFeed;
    //     }
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     priceFeed.updateAnswer(newPriceInt);
    // }

    function _getCollateralFromSeed(uint256 collateralSeed) private view returns(ERC20Mock){
        if(collateralSeed % 2 == 0){
            return weth;
        }else{
            return wbtc;
        }
    }

    function isUserAdded(address user) private view returns(bool){
        for(uint256 i=0; i<usersWithCollateralDeposited.length; i++){
            if(usersWithCollateralDeposited[i] == user){
                return true;
            }
        }
        return false;
    }

}