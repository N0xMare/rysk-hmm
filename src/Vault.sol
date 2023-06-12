// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { ERC4626 } from "solmate/mixins/ERC4626.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "solmate/utils/FixedPointMathLib.sol";

/// @notice rysk stuff
import { ILiquidityPool } from "./interfaces/ILiquidityPool.sol";
import { IOptionExchange } from "./interfaces/IOptionExchange.sol";
import { IOptionRegistry } from "./interfaces/IOptionRegistry.sol";
import { IAccounting } from "./interfaces/IAccounting.sol";
import { IController } from "./interfaces/IGammaInterface.sol";
import { IBeyondPricer } from "./interfaces/IBeyondPricer.sol";
import { Types } from "./libraries/Types.sol";
import { CombinedActions } from "./libraries/CombinedActions.sol";
import { RyskActions } from "./libraries/RyskActions.sol";

/// @notice Tokenized Vault for Rysk Options Market, Wheel Trading Strategy
contract Vault is ERC4626 {

    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        EVENTS                              */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice emitted when execute is called
    // foreach call to execute there is a nonce, `operateCallNonce`
    // foreach operation within the operation procedure struct there is a nonce, `operationNonce`
    event Execute(
        uint256 indexed operateCallNonce, 
        uint256 indexed operationNonce, 
        CombinedActions.ActionArgs action, 
        CombinedActions.OperationType operationType
    );

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        ERRORS                              */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error LiquidityLocked();
    error InsufficientAmount();
    error OnlyFundOperator();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        STORAGE                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice reserves
    uint256 public usdcReserves;

    /// @notice operator
    address public fundOperator;

    /// @notice operate() nonce
    uint256 public operateCallNonce;
    /// @notice 
    uint256 public operationNonce;

    /// @notice strategy contracts
    ILiquidityPool public liquidityPool;
    IOptionExchange public optionExchange;
    IOptionRegistry public optionRegistry;
    IBeyondPricer public beyondPricer;

    /// @notice Epoch Definition
    uint256 internal constant LIQUIDITY_LOCK_PERIOD = 6 days;
    uint256 internal constant LIQUIDITY_UNLOCK_PERIOD = 1 days;
    uint256 internal startEpoch;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     CONSTRUCTOR                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice constructor parameters | solmate ERC4626 implementation
    /// @param _asset underlying vault asset (USDC)
    /// @param _controller controller contract we need to call setOperator on to approve use of OptionExchange
    /// @param _optionExchange option exchange contract
    /// @param _optionRegistry option registry contract
    /// @param _liquityPool liquidity pool contract
    constructor(
        ERC20 _asset,
        IController _controller,
        address _optionExchange,
        address _optionRegistry,
        address _liquityPool)
        ERC4626(_asset, "Rysk USDC Vault", "ryskUSDC")
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

    /**
     * @notice deposit "assets" (USDC) into vault
     * @param assets amount of "assets" (USDC) to deposit
     * @param receiver address to send "shares" (HOMM) to
     */
    function deposit(uint256 assets, address receiver) public override returns (uint256 shares) {
        if (this.isLocked()) revert LiquidityLocked();
        // deposit
        shares = super.deposit(assets, receiver);
        // update reserves
        usdcReserves += assets;
    }

    /**
     * @notice mint "shares" Vault shares (HOMM) to "receiver" by depositing "assets" (USDC) of underlying tokens.
     */
    function mint(uint256 shares, address receiver) public override returns (uint256 assets) {
        if (this.isLocked()) revert LiquidityLocked();
        // mint
        assets = super.mint(shares, receiver);
        // update reserves
        usdcReserves += assets;
    }

    /**
     * @notice withdraw "asset" from vault
     * @param assets amount of "asset" (USDC) to withdraw
     * @param receiver address to send "asset" (USDC) to
     * @param owner address of owner
     */
    function withdraw(uint256 assets, address receiver, address owner) public override returns (uint256 shares) {
        if (this.isLocked()) revert LiquidityLocked();
        // withdraw
        shares = super.withdraw(assets, receiver, owner);
        // update reserves
        usdcReserves -= assets;
    }

    /**
     * @notice burn "shares" Vault shares (HOMM) from "owner" and sends "assets" (USDC) of underlying tokens to "receiver".
     */
    function redeem(uint256 shares, address receiver, address owner) public override returns (uint256 assets) {
        if (this.isLocked()) revert LiquidityLocked();
        // burn
        assets = super.redeem(shares, receiver, owner);
        // update reserves
        usdcReserves -= assets;
    }

    /**
     * @notice Returns the total amount of "assets" (USDC) held by this contract.
     */
    function totalAssets() public view override returns (uint256 assets) {
        return asset.balanceOf(address(this));
    }

    /**
     * @notice Returns true if deposits/withdraws are locked
     */
    function isLocked() external view returns (bool) {
        // compute # of epochs so far
        uint256 epochs = (block.timestamp - startEpoch) / (LIQUIDITY_LOCK_PERIOD + LIQUIDITY_UNLOCK_PERIOD);
        uint256 t0 = startEpoch + epochs * (LIQUIDITY_LOCK_PERIOD + LIQUIDITY_UNLOCK_PERIOD);
        return block.timestamp > t0 && block.timestamp <= t0 + LIQUIDITY_LOCK_PERIOD;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  FUND OPERATOR FUNCTIONS                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice OptionExchange Functions ////////////////////////

    /** Struct specification for OperateProcedure
    ----------------------------------------------------------------
    struct OptionSeries {                  |    enum ActionType {
        uint64 expiration;                 |        Issue,
        uint128 strike;                    |        BuyOption,
        bool isPut;                        |        SellOption,
        address underlying;                |        CloseOption
        address strikeAsset;               |    }
        address collateral;                |
	}                                      |
    ----------------------------------------------------------------
    struct ActionArgs {                    |    enum OperationType {
        ActionType actionType;             |        OPYN,
        address secondAddress;             |        RYSK
        address asset;                     |    }
        uint256 vaultId;                   |
        uint256 amount;                    |
        Types.OptionSeries optionSeries;   |
        uint256 acceptablePremium;         |
        bytes data;                        |
    }
    ----------------------------------------------------------------
    struct OperationProcedures {
        CombinedActions.OperationType operation;
        CombinedActions.ActionArgs[] operationQueue;
    }
    */
    /**
     * @notice execute actions on Rysk
     * @param _operateProcedures array of operations to execute on Rysk
     */
    function execute(IOptionExchange.OperationProcedures[] memory _operateProcedures) public {
        if (msg.sender != fundOperator) revert OnlyFundOperator();

        // execute action with capital within this contract
        IOptionExchange(optionExchange).operate(_operateProcedures);
        operateCallNonce++;
        for(uint16 i = 0; i < _operateProcedures.length; i++) {
            for (uint16 j = 0; j < _operateProcedures[i].operationQueue.length; j++) {
                operationNonce++;
                emit Execute(operateCallNonce, operationNonce, _operateProcedures[i].operationQueue[j], _operateProcedures[i].operation);
            }
        }
    }

    /// @notice OptionRegistry ///////////////////////////////////

    /**
     * @notice redeem option series on Rysk
     * @param _series the address of the option token to be burnt and redeemed
     * @return amount of underlying asset amount returned
     */
    function redeemOptionTokens(address _series) public returns (uint256) {
        if (msg.sender != fundOperator) revert OnlyFundOperator();
        // redeem option tokens
        return IOptionRegistry(optionRegistry).redeem(_series);
    }

    /// @notice BeyondPricer ///////////////////////////////////

    function quoteOptionPrice(
        Types.OptionSeries memory _optionSeries,
        uint256 _amount,
        bool _isSell,
        int256 _netDhvExposure
    ) external view returns (uint256 totalPremium, int256 totalDelta, uint256 totalFees) {
        if (msg.sender != fundOperator) revert OnlyFundOperator();
        // get option price from BeyondPricer
        return IBeyondPricer(beyondPricer).quoteOptionPrice(_optionSeries, _amount, _isSell, _netDhvExposure);
    }
}