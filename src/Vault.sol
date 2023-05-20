// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import  {ERC4626 } from "solmate/mixins/ERC4626.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "solmate/utils/FixedPointMathLib.sol";

/// @notice rysk shtuff
import { ILiquidityPool } from "./interfaces/ILiquidityPool.sol";
import { IOptionExchange } from "./interfaces/IOptionExchange.sol";
import { IOptionRegistry } from "./interfaces/IOptionRegistry.sol";


/// @notice High Order Market Making Vault (HOMM Vault)
contract Vault is ERC4626 {

    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    error LiquidityLocked();
    error InsufficientAmount();
    error OnlyOperator();

    // operator
    address public operator;

    // strategy contract
    ILiquidityPool public liquidityPool;
    IOptionExchange public optionExchange;
    IOptionRegistry public optionRegistry;

    /// @notice Epoch Definition
    uint256 internal constant LIQUIDITY_LOCK_PERIOD = 6 days;
    uint256 internal constant LIQUIDITY_UNLOCK_PERIOD = 1 days;
    uint256 internal startEpoch;

    // ERC20("HOMM Pool Token", "HOMM")
    constructor(address _asset, address _optionExchange, address _optionRegistry, address _liquityPool) ERC4626(ERC20(_asset), "HOMM Pool Token", "HOMM") {
        operator = msg.sender;
        optionExchange = IOptionExchange(_optionExchange);
        optionRegistry = IOptionRegistry(_optionRegistry);
        liquidityPool = ILiquidityPool(_liquityPool);
        startEpoch = block.timestamp;
    }

    // deposit USDC
    // Mints "shares" Vault shares to "receiver" by depositing exactly "assets" of underlying tokens.
    function deposit(uint256 assets, address receiver) public override returns (uint256 shares) {
        //extra logic
        if (this.isLocked()) revert LiquidityLocked();
        // deposit
        super.deposit(assets, receiver);
    }

    // mint HOMM
    // Mints exactly "shares" Vault shares to "receiver" by depositing "assets" of underlying tokens.
    function mint(uint256 shares, address receiver) public override returns (uint256 assets) {
        // extra logic
        if (this.isLocked()) revert LiquidityLocked();
        // mint
        super.mint(shares, receiver);
    }

    // withdraw USDC
    // Burns "shares" from owner and sends exactly "assets" of underlying tokens to "receiver".
    function withdraw(uint256 assets, address receiver, address owner) public override returns (uint256 shares) {
        // extra logic
        if (this.isLocked()) revert LiquidityLocked();
        //if () revert OperatorActive();
        // withdraw
        super.withdraw(assets, receiver, owner);
    }

    // burn HOMM
    // Burns exactly "shares" from owner and sends "assets" of underlying tokens to "receiver".
    function redeem(uint256 shares, address receiver, address owner) public override returns (uint256 assets) {
        // extra logic
        if (this.isLocked()) revert LiquidityLocked();
        //if () revert OperatorActive();
        // burn
        super.redeem(shares, receiver, owner);
    }

    /// @notice return balanceOf USDC held by this contract
    function totalAssets() public view override returns (uint256 assets) {
        return asset.balanceOf(address(this));
    }

    function isLocked() external view returns (bool) {
        // compute # of epochs so far
        uint256 epochs = (block.timestamp - startEpoch) / (LIQUIDITY_LOCK_PERIOD + LIQUIDITY_UNLOCK_PERIOD);
        uint256 t0 = startEpoch + epochs * (LIQUIDITY_LOCK_PERIOD + LIQUIDITY_UNLOCK_PERIOD);
        return block.timestamp > t0 && block.timestamp < t0 + LIQUIDITY_LOCK_PERIOD;
    }

    /// @notice Operator only functions

    //////////////////////////////////////////////////////////////
    /// @notice Liquidity Pool 
    //////////////////////////////////////////////////////////////

    function depositLiquidity(uint256 _amount) public {
        if (msg.sender != operator) revert OnlyOperator();

        // deposit liquidity to liquidity pool
        ILiquidityPool(liquidityPool).deposit(_amount);
    }

    // generate withdrawal reciept for share amount operator input
    function initiateWithdraw(uint256 _shares) public {
        if (msg.sender != operator) revert OnlyOperator();

        // initiate withdraw liquidity from liquidity pool
        ILiquidityPool(liquidityPool).initiateWithdraw(_shares);
    }

    // complete withdrawal from liquidity pool using existing reciept
    function completeWithdraw() public {
        if (msg.sender != operator) revert OnlyOperator();

        // withdraw liquidity from liquidity pool
        ILiquidityPool(liquidityPool).completeWithdraw();
    }

    //////////////////////////////////////////////////////////////
    /// @notice OptionExchange
    //////////////////////////////////////////////////////////////

    /**
    struct OptionSeries {
		uint64 expiration;
		uint128 strike;
		bool isPut;
		address underlying;
		address strikeAsset;
		address collateral;
	}

    enum ActionType {
        Issue,
        BuyOption,
        SellOption,
        CloseOption
    }

    struct ActionArgs {
        ActionType actionType;
        address secondAddress;
        address asset;
        uint256 vaultId;
        uint256 amount;
        Types.OptionSeries optionSeries;
        uint256 acceptablePremium;
        bytes data;
    }

    enum OperationType {
		OPYN,
		RYSK
	}

    struct OperationProcedures {
        CombinedActions.OperationType operation;
        CombinedActions.ActionArgs[] operationQueue;
    }
     */
    function tradeOption(IOptionExchange.OperationProcedures[] memory _operateProcedures) public {
        if (msg.sender != operator) revert OnlyOperator();

        // make trade with capital within this contract
        IOptionExchange(optionExchange).operate(_operateProcedures);
    }

    //////////////////////////////////////////////////////////////
    /// @notice OptionRegistry
    //////////////////////////////////////////////////////////////

    function redeemOptionTokens(address _series) public {
        if (msg.sender != operator) revert OnlyOperator();

        // redeem option tokens
        IOptionRegistry(optionRegistry).redeem(_series);
    }

    //////////////////////////////////////////////////////////////
    /// @notice Controller
    //////////////////////////////////////////////////////////////



    /// @notice Liquidation Stuff

    //function liquidate(uint256 _seriesId) public {
    //    if (msg.sender != operator) revert OnlyOperator();
    //    // liquidate 
    //}
}