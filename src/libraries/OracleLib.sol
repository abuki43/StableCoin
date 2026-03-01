// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

// this library is used to check the chainlink oracle for stale data.
// if a price is stale, the function will revert and render DSCEngine unstable .
library OracleLib {
    error OracleLib__StalePrice();
    uint256 private constant TIMEOUT = 3 hours;

    function staleCheckLatestRoundData(AggregatorV3Interface priceFeed) 
        public 
        view
        returns (uint80,int256,uint256,uint256,uint80)
        {
            (
                uint80 roundID,
                int256 answer,
                uint256 startedAt,
                uint256 updatedAt,
                uint80 answeredInRound
            ) = priceFeed.latestRoundData();
            uint256 timeSinceUpdate = block.timestamp - updatedAt;
            if (timeSinceUpdate > TIMEOUT) {
                revert OracleLib__StalePrice();
            }
            return (roundID, answer, startedAt, updatedAt, answeredInRound);
        }
}