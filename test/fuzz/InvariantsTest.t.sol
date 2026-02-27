// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// invariants

// 1) the total supply of DSC should be less than the total value of collateral
// 2) Getter view functions should not revert

import {Test,console2} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

contract InvariantsTest is StdInvariant,Test {
    DeployDSC deployer;
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address weth;
    address wbtc;
    Handler handler;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc,dsce,config) = deployer.run();
        (,, weth, wbtc,) = config.activeNetworkConfig();
        // targetContract(address(dsce));
        handler = new Handler(dsce,dsc);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dsce));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dsce));

        uint256 wethValue = dsce.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = dsce.getUsdValue(wbtc, totalWbtcDeposited);

        console2.log("total supply",totalSupply);

        uint256 totalCollateralValue = wethValue + wbtcValue;

        assert(totalCollateralValue >= totalSupply);
        console2.log("mint called",handler.timesMintIsCalled());
    }

    function invariant_getterFunctionsShouldNotRevert() public view {
        dsce.getCollateralTokens();
        dsce.getLiquidationBonus();
        dsce.getLiuidationThreshold();
        dsce.getDsc();
    }



}