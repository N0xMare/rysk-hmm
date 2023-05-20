// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { ILiquidityPool } from "./interfaces/ILiquidityPool.sol";

/*
liquidationFund:
   eth_pool: balance
   usdc_pool: balance

   deposit_collateral(amount):
       """"Here we add to the appropriate pool and return a token representing a share of the pool""""
   withdraw_collateral(amount)
     """"We burn the recived token and tx the  collateral to the reciver"""

   trade_option(optionSeries, amount, side):
       """Owneer only, I.e. our gnosis safe smart contract"""

    redeem(orderId)
       """We settle options we had bought which expired in the money"""

     liquidate(seriesId)
     """We check if its profitable to perform the liquidation if so we do it """
*/

/// @title Rysk High Order Market Maker

/*contract RyskHmm is ERC20 {
    ///@notice Events
    event Deposit(address indexed sender, uint256 amount);
    event Withdraw(address indexed sender, uint256 amount);
    event Trade(address indexed sender, uint256 optionSeries, uint256 amount, bool side);
    event Redeem(address indexed sender, uint256 orderId);
    // event Liquidate(address indexed sender, uint256 seriesId);

    /// @notice Errors
    error LiquidityLocked();
    error InsufficientAmount();
    error OnlyOperator();
    error Insolvent();
    error ReentrancyGuard();

    /// @notice external storage
    // operator
    address public operator;
    // rysk contracts
    ILiquidityPool public liquidityPool;
    // pool reserve state
    uint256 public usdcReserves;
    // start epoch timestamp
    uint256 public startEpoch;
    
    // upcoming deposits
    // mapping that stores msg.senders deposits from calls to initiateDeposit
    // mapping(address => uint256) public deposits;

    /// @notice internal storage
    uint256 internal lock = 1;

    /// @notice Epoch Definition
    uint256 internal constant LIQUIDITY_LOCK_PERIOD = 6 days;
    uint256 internal constant LIQUIDITY_UNLOCK_PERIOD = 1 days;

    /// @notice Minimum deposit amount
    uint256 internal constant MINIMUM_AMOUNT = 10 ** 3;
    
    constructor(address _liquidityPool, address _beyondPricer, address _operator) 
        ERC20("Rysk HMM Pool Token", "RHMM", 18) {
        liquidityPool = ILiquidityPool(_liquidityPool);
        operator = _operator;
        startEpoch = block.timestamp;
    }

    //function initiateDeposit(uint256 _amount) public {}

    function deposit(uint256 _amount) public {
        // safety checks
        if (lock > 1) {
            revert ReentrancyGuard();
        }
        lock = 2;
        if (this.isLocked()) revert LiquidityLocked();
        if (_amount < MINIMUM_AMOUNT) revert InsufficientAmount();

        // update reserve state
        usdcReserves += _amount;

        // mint pool tokens to user
        _mint(msg.sender, _amount);

        // deposit into liquidity pool
        liquidityPool.deposit(_amount);
        lock = 1;
    }

    function withdraw(uint256 _amount) public {
        // safety checks
        if (lock > 1) {
            revert ReentrancyGuard();
        }
        lock = 2;
        if (this.isLocked()) revert LiquidityLocked();
        if (_amount < MINIMUM_AMOUNT) revert InsufficientAmount();
        // check if enough usdc reserves for withdrawal

        // update reserve state
        usdcReserves -= _amount;

        // burn pool tokens from user

        // withdraw from liquidity pool
        liquidityPool.withdraw(_amount);
        lock = 1;
    }

    function tradeOption(uint256 _optionSeries, uint256 _amount, bool _side) public {
        if (msg.sender != operator) revert OnlyOperator();
        // make trade with capital within this contract

    }

    function redeem(uint256 _orderId) public {

    }

    function liquidate(uint256 _seriesId) public {

    }

    function isLocked() external view returns (bool) {
        // compute # of epochs so far
        uint256 epochs = (block.timestamp - startEpoch) / (LIQUIDITY_LOCK_PERIOD + LIQUIDITY_UNLOCK_PERIOD);
        uint256 t0 = startEpoch + epochs * (LIQUIDITY_LOCK_PERIOD + LIQUIDITY_UNLOCK_PERIOD);
        return block.timestamp > t0 && block.timestamp < t0 + LIQUIDITY_LOCK_PERIOD;
    }
}*/
