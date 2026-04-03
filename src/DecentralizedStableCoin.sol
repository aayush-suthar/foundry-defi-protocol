// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title DecentralizedStableCoin
 * @author Aayush
 * Collateral : Exogenous (ETH & BTC)
 * Minting : Algorithmic
 * Relative Stability : Pegged to USD
 * 
 * This is the contract meant to be governed by DSCEngine. This contract is just the ERC20
 * implementation of our stablecoin system
 * 
 */

// ERC20Burnable has burn function
contract DecentralizedStableCoin is ERC20Burnable, Ownable{
    error DecentralizedStableCoin__MustBeMoreThanZero();
    error DecentralizedStableCoin__BurnAmountExceedsBalance();
    error DecentralizedStableCoin__NotZeroAddress();
    
    constructor() ERC20("DecentralizedStableCoin", "DSC") Ownable(msg.sender){}

    function burn(uint256 _amount) public override onlyOwner{
        uint256 balance = balanceOf(msg.sender);
        if(_amount <= 0){
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }
        if(balance < _amount){
            revert DecentralizedStableCoin__BurnAmountExceedsBalance();
        }
        // use the burn function from parent (ERC20burner) class
        // since we are overriding it, we need to use super to again use the same function from parent class
        super.burn(_amount); 
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns(bool) {
        if(_to == address(0)){
            revert DecentralizedStableCoin__NotZeroAddress();
        }
        if(_amount <= 0){
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}