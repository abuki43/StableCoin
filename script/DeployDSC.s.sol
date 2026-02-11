// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from 'forge-std/Script.sol';
import {DSCEngine} from '../src/DSCEngine.sol';
import {DecentralizedStableCoin} from '../src/DecentralizedStableCoin.sol';


contract DeployDSC is Script {
    function run() external returns (DSCEngine, DecentralizedStableCoin) {
        vm.startBroadcast();

        DecentralizedStableCoin dsc = new DecentralizedStableCoin();
        DSCEngine dscEngine = new DSCEngine(tokenCollateralAddresses, priceFeedAddresses, address(dsc));

        dsc.transferOwnership(address(dscEngine));

        vm.stopBroadcast();

        return (dscEngine, dsc);
      
    }
}