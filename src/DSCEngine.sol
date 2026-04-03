// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from '../src/DecentralizedStableCoin.sol';
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
/**
 * @title DSCEngine
 * @author Aayush
 * 
 * The system is designed to be as minimal as possible and have the token maintains a 1 token == $1 peg
 * The stablecoin has the properties:
 *      - Exogenous Collateral
 *      - Dollar pegged
 *      - Algorithmic Stable
 * 
 * It is similar to DAI if DAI has no governance, no fees, and was only backed by WETH and WBTC
 * 
 * Our DSC system should always be "OverCollateral". At no point, should the value of all collateral <= the $ backed value of all the DSC.
 * 
 * @notice This contract is the core of the DSC System. It handles all the logic for mining
 * and redeeming DSC, as well as depositing & withdrawing collaterals.
 * @notice This contract is VERY lossely based on the MakerDAO DSS (DAI) system.
 */

contract DSCEngine is ReentrancyGuard{

    /*** Errors ***/
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressAndPriceFeedAddressMstBeSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 heathFactor);
    error DSCEngine__MintFailed();

    /*** State Variables ***/
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% collaterized  ((100/50) * 100)% = 200%
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;


    mapping(address token => address priceFeed) private s_priceFeeds; // tokenToPriceFeed
    DecentralizedStableCoin private immutable i_dsc;
    mapping(address user => mapping(address token => uint256)) private s_collateralDeposited;
    mapping(address user => uint256 amountDSCMinted) private s_DSCMinted;
    address[] private s_collateralTokens;


    /*** Events ***/
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);



    /*** MODIFIERS ***/
    modifier moreThanZero(uint256 amount){
        if(amount == 0){
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowToken(address token){
        if(s_priceFeeds[token] == address(0)){
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }


    /*** Functions  ***/
    // tokenAddress : [WETH_Address, WBTC_Address]
    // priceFeedAddress : [WETH_USD_Oracle_Address, WBTC_USD_Oracle_Address]
    constructor(address[] memory tokenAddress, address[] memory priceFeedAddress, address dscAddress) {
        if(tokenAddress.length != priceFeedAddress.length){
            revert DSCEngine__TokenAddressAndPriceFeedAddressMstBeSameLength();
        }
        for(uint256 i = 0 ; i < tokenAddress.length ; i++){
            s_priceFeeds[tokenAddress[i]] = priceFeedAddress[i];
            s_collateralTokens.push(priceFeedAddress[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }



    /*** External Functions  ***/
    function depositCollateralAndMintDSC() external {}

    /**
     * @notice follows CEI 
     * @param tokenCollateralAddress The address of the token to deposit as collateral 
     * @param amountCollateral The amount of collateral to deposit
     * 
     * good practice to use nonReentrant when working with external functions
     *  
     */
    function depositCollateral(address tokenCollateralAddress , uint256 amountCollateral) external moreThanZero(amountCollateral) isAllowToken(tokenCollateralAddress) nonReentrant{
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral; 
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        /*When you wrap the address in IERC20(...), you are forcefully typecasting it. You are telling the compiler:
"I guarantee you that the code deployed at this specific address perfectly follows the ERC-20 token standard. Put the 'ERC-20 Lens' over this address so I  can interact with it." */
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if(!success){
            revert DSCEngine__TransferFailed();
        }
    }
    
    // Threshold to let say 150% 
    // in under collateral system, if someone pays back your minted DSC, they can have all your collateral for a discount.
    function redeemCollateralForDSC() external {}

    function redeemCollateral() external {}


    /**
     * @notice follows CEI
     * @param amountDSCToMint The amount of decntralized stablecoin to mint
     * @notice they must have more collateral value than the minimum threshold
     */
    function mintDSC(uint256 amountDSCToMint) external moreThanZero(amountDSCToMint) nonReentrant{
        s_DSCMinted[msg.sender] += amountDSCToMint;
        // if they minted to much
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDSCToMint);
        if(!minted){
            revert DSCEngine__MintFailed();
        }
    }

    function burnDSC() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}


    /*** Private & Internal view Functions  ***/    

    function _getAccountInformation(address user) private view returns (uint256 totalDscMinted, uint256 collateralValueInUsd){
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /**
     * Returns how close to liquidation a user is
     * If a user goes below 1, then they can get liquidated
     */
    function _healthFactor(address user) private view returns (uint256){
        // total DSC minted
        // total Collateral value
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);

        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        /**
         *   collateral
         * --------------    < 1 ---> UNDER COLLATERIZED
         * DSC worth * 200%  
         */

        /**
         * 
         * $1000 ETH / 100 DSC
         * collateralAdjustedForThreshold = ((1000) * 50)/100 = 500
         * ratio : (500)/(100) = 5 >= 1 --> OVER COLLATERIZED
         * 
         */

        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;        
    }

        // 1. Check health factor (do they have enough collateral)
        // 2. Revert if they don't
    function _revertIfHealthFactorIsBroken(address user) internal view{
        uint256 userHealthFactor = _healthFactor(user);
        if(userHealthFactor < MIN_HEALTH_FACTOR){
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }



    /*** Public & External view Functions  ***/    

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd){
        // loop through each collateral token, get the amount they have deposited, and map it to the price, to get the USD value

        for(uint256 i = 0 ; i < s_collateralTokens.length ; i++){
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token , amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (,int256 price,,,) = priceFeed.latestRoundData();
        // Let say 1 ETH = $1000
        // the returned value price from chainlink will be 1000 * 1e8
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount)/PRECISION;
    }

}