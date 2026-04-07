// Handler is going to narrow down the way we call function
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

// price feed
// WETH Token
// WBTC Token

contract Handler is Test {
    DSCEngine engine;
    DecentralizedStableCoin dsc;

    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 public timeMintIsCalled; // some ghost variable
    address[] public userWithCollateralDeposited;
    MockV3Aggregator public ethUsdPriceFeed;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(DSCEngine _engine, DecentralizedStableCoin _dsc) {
        engine = _engine;
        dsc = _dsc;

        address[] memory collateralToken = engine.getCollateralTokens();
        weth = ERC20Mock(collateralToken[0]);
        wbtc = ERC20Mock(collateralToken[1]);

        ethUsdPriceFeed = MockV3Aggregator(engine.getCollateralTokenPriceFeed(address(weth)));
    }

    // redeemCollateral
    // parameters will be random
    // collateralSeed -> random, but collateral will be a valid type
    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1 , MAX_DEPOSIT_SIZE);
        
        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        // approve is only during pull (extract collateral) not push
        collateral.approve(address(engine), amountCollateral);
        engine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        userWithCollateralDeposited.push(msg.sender);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateral = engine.getCollateralBalanceOfUser(msg.sender, address(collateral));

        if(maxCollateral == 0){
            return;
        }

        amountCollateral = bound(amountCollateral, 1 , maxCollateral);
        
        vm.startPrank(msg.sender);
        engine.redeemCollateral(address(collateral), amountCollateral);
        vm.stopPrank();      
    }

    function minDsc(uint256 amount, uint256 addressSeed) public {
        if(userWithCollateralDeposited.length == 0){
            return;
        }
        address sender = userWithCollateralDeposited[addressSeed % userWithCollateralDeposited.length];

        vm.startPrank(sender);
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(sender);

        int256 maxDscToMint = (int256(collateralValueInUsd) / 2) - int256(totalDscMinted);

        if(maxDscToMint <= 0){
            return;
        }
        amount = bound(amount, 1, uint256(maxDscToMint));

        engine.mintDSC(amount);
        vm.stopPrank();
        timeMintIsCalled++;
    }

    // invariant will break if price drops
    // function updateCollateralPrice(uint96 newPrice) public {
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     ethUsdPriceFeed.updateAnswer(newPriceInt);
    // }

    /* Helper functions */
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed %2 == 0){
            return weth;
        } else {
            return wbtc;
        }
    } 

}