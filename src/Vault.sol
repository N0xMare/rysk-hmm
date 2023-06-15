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

    /// @notice emitted when withdrawal is completed by the operator
    event WithdrawalCompleted(address indexed recipient, uint256 amount);

    /// @notice emitted when execute() is called
    // foreach execute() call there is a nonce, `operateCallNonce`
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

    error WithdrawalAmountErr();
    error PendingWithdrawalAmountErr();
    error InsufficientAmount();
    error InsufficientReserves();
    error InvalidOperation();
    error OnlyFundOperator();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        STORAGE                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice reserves, USDC balance of this contract
    uint256 public usdcReserves;
    /// @notice active capital, USDC balance deployed in vault strategy managed by the operator
    uint256 public activeCapital;

    /// @notice pending withdrawals map (receiver => amount)
    mapping(address => uint256) public pendingWithdrawals;
    /// @notice pending withdrawals address array
    address[] public pendingWithdrawAddresses;
    /// @notice pending withdrawals total
    uint256 public pendingWithdrawalsTotal;

    /// @notice operator
    address public fundOperator;

    /// @notice operate() nonce
    uint256 public operateCallNonce;
    /// @notice operation nonce
    uint8 public operationNonce;

    /// @notice strategy contracts
    // Rysk DHV liquidity pool
    ILiquidityPool public liquidityPool;
    // Rysk option exchange
    IOptionExchange public optionExchange;
    // Rysk option registry
    IOptionRegistry public optionRegistry;
    // Rysk options pricing
    IBeyondPricer public beyondPricer;

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
        // set optionExchange as operator in controller
        _controller.setOperator(address(optionExchange), true);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  EXTERNAL USER FUNCTIONS                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice deposit "assets" (USDC) into vault
     * @param assets amount of "assets" (USDC) to deposit
     * @param receiver address to send "shares" to
     * @return shares amount of Vault shares minted
     */
    function deposit(uint256 assets, address receiver) public override returns (uint256 shares) {
        // deposit
        shares = super.deposit(assets, receiver);
        // update reserves
        usdcReserves += assets;
    }

    /**
     * @notice mint "shares" Vault shares to "receiver" by depositing "assets" (USDC) of underlying tokens.
     * @param shares amount of Vault shares to mint
     * @param receiver address to send "shares" to
     * @return assets amount of "assets" (USDC) deposited
     */
    function mint(uint256 shares, address receiver) public override returns (uint256 assets) {
        // mint
        assets = super.mint(shares, receiver);
        // update reserves
        usdcReserves += assets;
    }


    /**
     * @notice initiate withdrawal of assets from vault to "receiver"
     * @param assets amount of "asset" (USDC) to withdraw
     * @param receiver address to send "asset" (USDC) to
     */
    /// NOTE: this function breaks if the same receiver address is used twice before the completeWithdrawal function is called
    function initiateWithdraw(uint256 assets, address receiver) public {
        if (assets == 0) {
            revert InsufficientAmount();
        }
        // total number of assets from msg.sender's share balance
        uint256 currentAssetsFromShares = convertToAssets(this.balanceOf(msg.sender));
        // total number of assets from msg.sender's receiver pending withdrawals
        uint256 currentWithdrawAmount = pendingWithdrawals[receiver];

        // user cannot withdraw more than their total balance
        if (currentAssetsFromShares < assets) {
            revert WithdrawalAmountErr();
        }
        if (currentAssetsFromShares < currentWithdrawAmount + assets) {
            revert PendingWithdrawalAmountErr();
        }

        // update pending withdrawals mapping
        pendingWithdrawals[receiver] += assets;

        // update total pending withdrawals
        pendingWithdrawalsTotal += assets;

        // Add the sender to the array of pending withdrawers
        pendingWithdrawAddresses.push(receiver);
    }

    /**
     * @notice initiate burning vault shares to sends "assets" (USDC) of underlying tokens to "receiver".
     * @param shares amount of "shares" to burn
     * @param receiver address to send "assets" (USDC) to
     */
    /// NOTE: this function breaks if the same receiver address is used twice before the completeWithdrawal function is called
    function initiateRedeem(uint256 shares, address receiver) public {
        if (shares == 0) {
            revert InsufficientAmount();
        }
        // total number of assets from msg.sender's share balance
        uint256 currentAssetsFromShares = convertToAssets(this.balanceOf(msg.sender));
        // assets amount to withdraw
        uint256 assets = convertToAssets(shares);
        // total number of assets from msg.sender's pending withdrawals
        uint256 currentWithdrawAmount = pendingWithdrawals[msg.sender];

        // user cannot withdraw more than their total balance
        if (currentAssetsFromShares < assets) {
            revert WithdrawalAmountErr();
        }
        if (currentAssetsFromShares < currentWithdrawAmount + assets) {
            revert PendingWithdrawalAmountErr();
        }

        // update pending withdrawals mapping
        pendingWithdrawals[receiver] += assets;

        // update total pending withdrawals
        pendingWithdrawalsTotal += assets;

        // Add the sender to the array of pending withdrawers
        pendingWithdrawAddresses.push(receiver);
    }

    /**
     * @notice Returns the total amount of "assets" (USDC) held by this contract.
     */
    function totalAssets() public view override returns (uint256 assets) {
        return asset.balanceOf(address(this));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  FUND OPERATOR FUNCTIONS                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Fund Withdrawal Function //////////////////

    /**
     * @notice complete pending withdrawals 
     * This is shitty design security wise :( maybe I try use receipt objects later
     */
    function completeWithdrawals() external {
        // check that the sender is the fund operator
        if (msg.sender != fundOperator) revert OnlyFundOperator();
    
        // execute transfers of usdc to each address with a pending withdrawal
        for (uint256 i = 0; i < pendingWithdrawAddresses.length; i++) {
            // receiver address
            address receiver = pendingWithdrawAddresses[i];
            // withdraw amount
            uint256 amount = pendingWithdrawals[receiver];
            // update pending withdrawals mapping to 0
            pendingWithdrawals[receiver] = 0;
            // update total pending withdrawals
            pendingWithdrawalsTotal -= amount;
            // transfer usdc to receiver
            asset.safeTransfer(receiver, amount);
            // update reserves
            usdcReserves -= amount;
            emit WithdrawalCompleted(receiver, amount);
        }
        // clear pending withdraw addresses
        delete pendingWithdrawAddresses;
    }

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
        RyskActions.OperationType operation;
        RyskActions.ActionArgs[] operationQueue;
    }
    ----------------------------------------------------------------
    */
    /**
     * @notice execute actions on Rysk (WIP)
     * @param _operateProcedures array of operations to execute on Rysk
     */
    function execute(IOptionExchange.OperationProcedures[] memory _operateProcedures) public {
        if (msg.sender != fundOperator) revert OnlyFundOperator();
        // iterate through _operateProcedures
        for(uint8 i = 0; i < _operateProcedures.length; i++) {
            // iterate through operationQueue
            for (uint8 j = 0; j < _operateProcedures[i].operationQueue.length; j++) {
                // OPYN
                if (_operateProcedures[i].operation == CombinedActions.OperationType.OPYN) {
                    // handle OPYN operations
                    // currently no checks on this, will be implemented later
                    IOptionExchange(optionExchange).operate(_operateProcedures);
                }
                // RYSK
                else if (_operateProcedures[i].operation == CombinedActions.OperationType.RYSK) {
                    // parse into RYSK operation
                    RyskActions.ActionArgs memory ryskAction = CombinedActions._parseRyskArgs(_operateProcedures[i].operationQueue[j]);

                    // ISSUE (0)
                    if (ryskAction.actionType == RyskActions.ActionType.Issue) {
                        // check option series expiration is not more than 30 days in the future
                        if (ryskAction.optionSeries.expiration > block.timestamp + 30 days) {
                            revert InvalidOperation();
                        }
                        // more safety checks here (WIP)
                        // measure slippage from beyondpricer, assert slippage tolerance

                        // operate
                        IOptionExchange(optionExchange).operate(_operateProcedures);
                        emit Execute(operateCallNonce, operationNonce, _operateProcedures[i].operationQueue[j], _operateProcedures[i].operation);

                        // decrease USDC reserves by amount used for issue, receive and track oToken issued by Rysk

                        // update reserves
                        usdcReserves -= ryskAction.amount;

                        // update local oToken(s) state (WIP)

                    // BUY OPTION (1)
                    } else if (ryskAction.actionType == RyskActions.ActionType.BuyOption) {
                        // lose USDC reserves, receive oToken from Rysk liquidity pool

                        // check option series expiration is not more than 30 days in the future
                        if (ryskAction.optionSeries.expiration > block.timestamp + 30 days) {
                            revert InvalidOperation();
                        }
                        // more safety checks here (WIP)

                        // operate
                        IOptionExchange(optionExchange).operate(_operateProcedures);
                        emit Execute(operateCallNonce, operationNonce, _operateProcedures[i].operationQueue[j], _operateProcedures[i].operation);

                        // decrease USDC reserves by amount used for buy, receive and track oToken issued by Rysk

                        // update reserves
                        usdcReserves -= ryskAction.amount;

                        // update local oToken(s) state (WIP)

                    // SELL OPTION (2)
                    } else if (ryskAction.actionType == RyskActions.ActionType.SellOption) {
                        // receive USDC reserves (premium), lose oToken
                        // assert acceptable premium/PnL

                        IOptionExchange(optionExchange).operate(_operateProcedures);

                        emit Execute(operateCallNonce, operationNonce, _operateProcedures[i].operationQueue[j], _operateProcedures[i].operation);

                    // CLOSE OPTION (3)
                    } else if (ryskAction.actionType == RyskActions.ActionType.CloseOption) {
                        // receive USDC reserves (premium), lose oToken to Rysk liquidity pool
                        // assert acceptable premium/PnL

                        IOptionExchange(optionExchange).operate(_operateProcedures);

                        emit Execute(operateCallNonce, operationNonce, _operateProcedures[i].operationQueue[j], _operateProcedures[i].operation);
                    }
                } else revert InvalidOperation();
            }
        }

        // execute action with capital within this contract
        //IOptionExchange(optionExchange).operate(_operateProcedures);

        /*operateCallNonce++;
        for(uint8 i = 0; i < _operateProcedures.length; i++) {
            for (uint8 j = 0; j < _operateProcedures[i].operationQueue.length; j++) {
                operationNonce++;
                emit Execute(operateCallNonce, operationNonce, _operateProcedures[i].operationQueue[j], _operateProcedures[i].operation);
            }
        }*/
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