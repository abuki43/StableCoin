// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from './DecentralizedStableCoin.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {AggregatorV3Interface} from '@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol';

contract DSCEngine is ReentrancyGuard {
    error DSCEngine__AmountMustBeAboveZero();
    error DSCEngine__TokenAddressAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__NotAllowedToken(address token);
    error DSCEngine__TransferFailed();
    error DSCEngine__HealthFactorTooLow(uint256 healthFactor);
    error DSCEngine__MintFailed();

    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1; 

    mapping(address token => address priceFeed) s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;
    address[] private s_collateralTokens;
    DecentralizedStableCoin private immutable i_dsc;

    event CollateralDeposited(address indexed user, address indexed tokenCollateralAddress, uint256 amountCollateral);

    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine__AmountMustBeAboveZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken(token);
        }
        _;
    }

    constructor(
        address[] memory tokenCollateralAddresses,
        address[] memory priceFeedAddresses,
        address dscAddress
    ) {
        if (tokenCollateralAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressAndPriceFeedAddressesMustBeSameLength();
        }
        for (uint256 i = 0; i < tokenCollateralAddresses.length; i++) {
            s_priceFeeds[tokenCollateralAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenCollateralAddresses[i]);
        }

        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    function depositCollateralAndMintDsc() external {}

    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }

    }

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}

    function mintDsc(uint256 amountDscToMint) external moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;

        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}

    function _getAccountInformation(address user) private view returns (uint256 totalDscMinted, uint256 collateralValueInUsd) {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    } 

    function _healthFactor(address user) private view  returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        uint256 adjustedCollateralValue = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        return (adjustedCollateralValue * PRECISION) / totalDscMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorTooLow( userHealthFactor);
        }
      
    }

    function getAccountCollateralValue(address user) public view returns (uint256) {
        uint256 totalCollateralValueInUsd;
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address tokenCollateralAddress = s_collateralTokens[i];
            uint256 amountCollateralDeposited = s_collateralDeposited[user][tokenCollateralAddress];
            if (amountCollateralDeposited > 0) {
                uint256 price = getUsdValue(tokenCollateralAddress,amountCollateralDeposited);
                totalCollateralValueInUsd += price;
            }
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns(uint256){
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price, , , ) = priceFeed.latestRoundData();
        uint8 decimals = priceFeed.decimals();
        return ((uint256(price) * amount) / (10 ** decimals));
    }
}
