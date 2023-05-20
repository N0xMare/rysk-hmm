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
import { IController } from "./interfaces/IGammaInterface.sol";


/// @notice High Order Market Making Vault (HOMM Vault)
contract Vault is ERC4626 {

    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        ERRORS                              */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error LiquidityLocked();
    error InsufficientAmount();
    error OnlyFundOperator();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        STORAGE                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice operator
    address public fundOperator;

    /// @notice strategy contracts
    ILiquidityPool public liquidityPool;
    IOptionExchange public optionExchange;
    IOptionRegistry public optionRegistry;

    /// @notice Epoch Definition
    uint256 internal constant LIQUIDITY_LOCK_PERIOD = 6 days;
    uint256 internal constant LIQUIDITY_UNLOCK_PERIOD = 1 days;
    uint256 internal startEpoch;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     CONSTRUCTOR                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice constructor parameters
    /// @param _controller controller contract we need to call setOperator on to approve use of OptionExchange
    /// @param _asset underlying vault asset (USDC)
    /// @param _optionExchange option exchange contract
    /// @param _optionRegistry option registry contract
    /// @param _liquityPool liquidity pool contract
    constructor(
        IController _controller,
        address _asset,
        address _optionExchange,
        address _optionRegistry,
        address _liquityPool) 
        ERC4626(ERC20(_asset), "HOMM Pool Token", "HOMM") 
        {
        // set fund operator
        fundOperator = msg.sender;
        optionExchange = IOptionExchange(_optionExchange);
        optionRegistry = IOptionRegistry(_optionRegistry);
        liquidityPool = ILiquidityPool(_liquityPool);
        startEpoch = block.timestamp;
        // set optionExchange as operator in controller
        _controller.setOperator(address(optionExchange), true);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  EXTERNAL USER FUNCTIONS                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice deposit "asset" into vault
    // Mints "shares" Vault shares to "receiver" by depositing exactly "assets" of underlying tokens.
    function deposit(uint256 assets, address receiver) public override returns (uint256 shares) {
        //extra logic
        if (this.isLocked()) revert LiquidityLocked();
        // deposit
        super.deposit(assets, receiver);
    }

    /// @notice mint HOMM
    // Mints exactly "shares" Vault shares to "receiver" by depositing "assets" (USDC) of underlying tokens.
    function mint(uint256 shares, address receiver) public override returns (uint256 assets) {
        // extra logic
        if (this.isLocked()) revert LiquidityLocked();
        // mint
        super.mint(shares, receiver);
    }

    /// @notice withdraw "asset" from vault
    // Burns "shares" from owner and sends exactly "assets" (USDC) of underlying tokens to "receiver".
    function withdraw(uint256 assets, address receiver, address owner) public override returns (uint256 shares) {
        // extra logic
        if (this.isLocked()) revert LiquidityLocked();
        //if () revert OperatorActive();
        // withdraw
        super.withdraw(assets, receiver, owner);
    }

    /// @notice burn HOMM
    // Burns exactly "shares" from owner and sends "assets" (USDC) of underlying tokens to "receiver".
    function redeem(uint256 shares, address receiver, address owner) public override returns (uint256 assets) {
        // extra logic
        if (this.isLocked()) revert LiquidityLocked();
        //if () revert OperatorActive();
        // burn
        super.redeem(shares, receiver, owner);
    }

    /// @notice return balanceOf "asset" (USDC) held by this contract
    function totalAssets() public view override returns (uint256 assets) {
        return asset.balanceOf(address(this));
    }

    /// @notice return true if vault is locked
    function isLocked() external view returns (bool) {
        // compute # of epochs so far
        uint256 epochs = (block.timestamp - startEpoch) / (LIQUIDITY_LOCK_PERIOD + LIQUIDITY_UNLOCK_PERIOD);
        uint256 t0 = startEpoch + epochs * (LIQUIDITY_LOCK_PERIOD + LIQUIDITY_UNLOCK_PERIOD);
        return block.timestamp > t0 && block.timestamp < t0 + LIQUIDITY_LOCK_PERIOD;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  FUND OPERATOR FUNCTIONS                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Liquidity Pool Functions ///////////////////////////

    function depositLiquidity(uint256 _amount) public {
        if (msg.sender != fundOperator) revert OnlyFundOperator();

        // deposit liquidity to liquidity pool
        ILiquidityPool(liquidityPool).deposit(_amount);
    }

    // generate withdrawal reciept for share amount operator input
    function initiateWithdraw(uint256 _shares) public {
        if (msg.sender != fundOperator) revert OnlyFundOperator();

        // initiate withdraw liquidity from liquidity pool
        ILiquidityPool(liquidityPool).initiateWithdraw(_shares);
    }

    // complete withdrawal from liquidity pool using existing reciept
    function completeWithdraw() public {
        if (msg.sender != fundOperator) revert OnlyFundOperator();

        // withdraw liquidity from liquidity pool
        ILiquidityPool(liquidityPool).completeWithdraw();
    }

    /// @notice OptionExchange Functions ////////////////////////

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
        if (msg.sender != fundOperator) revert OnlyFundOperator();

        // make trade with capital within this contract
        IOptionExchange(optionExchange).operate(_operateProcedures);
    }

    /// @notice OptionRegistry ///////////////////////////////////

    function redeemOptionTokens(address _series) public {
        if (msg.sender != fundOperator) revert OnlyFundOperator();

        // redeem option tokens
        IOptionRegistry(optionRegistry).redeem(_series);
    }
}