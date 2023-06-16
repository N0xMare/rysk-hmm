// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @notice solmate
import { ERC4626 } from "solmate/mixins/ERC4626.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "solmate/utils/FixedPointMathLib.sol";

/// @notice rysk
// interfaces
import { ILiquidityPool } from "./interfaces/ILiquidityPool.sol";
import { IOptionExchange } from "./interfaces/IOptionExchange.sol";
import { IOptionRegistry } from "./interfaces/IOptionRegistry.sol";
import { IAccounting } from "./interfaces/IAccounting.sol";
import { IController } from "./interfaces/IGammaInterface.sol";
import { IBeyondPricer } from "./interfaces/IBeyondPricer.sol";
import { IAlphaPortfolioValuesFeed } from "./interfaces/IAlphaPortfolioValuesFeed.sol";
// libraries
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
    error PendingWithdrawalAddressErr();
    error NoPendingWithdrawals();
    error InsufficientAmount();
    error InsufficientReserves();
    error InvalidOperation();
    error OnlyFundOperator();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        STORAGE                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    struct Withdrawal {
        uint256 amount;
        address next;
    }

    /// @notice reserves, USDC balance of this contract
    uint256 public usdcReserves;
    /// @notice active capital, USDC balance deployed in vault strategy managed by the operator
    uint256 public activeCapital; 
    // NOTE: PnL calc, is checking assets received back from trades with activeCapital amount we txs out of vault

    /// @notice pending withdrawals map (receiver => Withdrawal(amount, next_receiver_addr))
    // kinda like a linked list, but not really
    mapping(address => Withdrawal) public pendingWithdrawals;
    /// @notice pending withdrawals size
    address public listSize;
    /// @notice pending withdrawals list head
    address constant head = address(1);
    /// @notice balances mapping
    mapping(address => uint256) public balances;

    /// @notice operator
    address public fundOperator;

    /// @notice operate() nonce
    uint256 public operateCallNonce;
    /// @notice operation nonce
    uint8 public operationNonce;

    /// @notice strategy contracts
    // Rysk option exchange
    address public optionExchange;
    // Rysk option registry
    address public optionRegistry;
    // Rysk DHV liquidity pool
    address public liquidityPool;
    // Rysk options pricing
    address public beyondPricer;
    // Rysk portfolio storage and calculations
    address public alphaPortfolioValuesFeed;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     CONSTRUCTOR                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice constructor parameters | solmate ERC4626-ish implementation
    /// @param _asset underlying vault asset (USDC)
    /// @param _controller controller contract we need to call setOperator on to approve use of OptionExchange
    /// @param _optionExchange option exchange contract
    /// @param _optionRegistry option registry contract
    /// @param _liquidityPool liquidity pool contract
    /// @param _beyondPricer beyond pricer contract
    /// @param _alphaPortfolioValuesFeed alpha portfolio values feed contract
    constructor(
        ERC20 _asset,
        address _controller,
        address _optionExchange,
        address _optionRegistry,
        address _liquidityPool,
        address _beyondPricer,
        address _alphaPortfolioValuesFeed
        )
        ERC4626(_asset, "Rysk USDC Vault", "ryskUSDC")
        {
        // set fund operator
        fundOperator = msg.sender;
        optionExchange = _optionExchange;
        optionRegistry = _optionRegistry;
        liquidityPool = _liquidityPool;
        beyondPricer = _beyondPricer;
        alphaPortfolioValuesFeed = _alphaPortfolioValuesFeed;
        // set optionExchange as operator in controller
        IController(_controller).setOperator(address(optionExchange), true);
        // initialize pending withdrawals
        pendingWithdrawals[head].next = head;
        pendingWithdrawals[head].amount = 0;
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
    function initiateWithdraw(uint256 assets, address receiver) public {
        if (assets == 0) {
            revert InsufficientAmount();
        }
        // total number of assets from msg.sender's share balance
        uint256 currentAssetsFromShares = convertToAssets(this.balanceOf(msg.sender));
        // total number of assets from msg.sender's receiver pending withdrawals
        uint256 currentWithdrawAmount = pendingWithdrawals[receiver].amount;

        // verify msg.sender has enough shares/assets for withdrawal
        // user cannot withdraw more than their total balance
        if (currentAssetsFromShares < assets) {
            revert WithdrawalAmountErr();
        }
        if (currentAssetsFromShares < currentWithdrawAmount + assets) {
            revert PendingWithdrawalAmountErr();
        }
        // assert reciever's next address is the zero address, 1 pending withdrawal per receiver
        if (pendingWithdrawals[receiver].next != address(0)) {
            revert PendingWithdrawalAddressErr();
        }

        // update pending withdrawals
        // new withdrawal inserted at the front of the list takes the current heads next address
        // can either be the head address `address(1)` if the list is empty, receiving its first element, or 
        // if the list is not empty the next address of the current head
        pendingWithdrawals[receiver] = Withdrawal({
            next: pendingWithdrawals[head].next,
            amount: assets
        });
        // update head to point to the new withdrawal receiver address
        pendingWithdrawals[head].next = receiver;
        // update list size
        listSize++;
    }

    /**
     * @notice initiate burning vault shares to sends "assets" (USDC) of underlying tokens to "receiver".
     * @param shares amount of "shares" to burn
     * @param receiver address to send "assets" (USDC) to
     */
    function initiateRedeem(uint256 shares, address receiver) public {
        if (shares == 0) {
            revert InsufficientAmount();
        }
        // total number of assets from msg.sender's share balance
        uint256 currentAssetsFromShares = convertToAssets(this.balanceOf(msg.sender));
        // assets amount to withdraw
        uint256 assets = convertToAssets(shares);
        // total number of assets from msg.sender's pending withdrawals
        uint256 currentWithdrawAmount = pendingWithdrawals[receiver].amount;

        // user cannot withdraw more than their total balance
        if (currentAssetsFromShares < assets) {
            revert WithdrawalAmountErr();
        }
        if (currentAssetsFromShares < currentWithdrawAmount + assets) {
            revert PendingWithdrawalAmountErr();
        }
        // assert reciever's next address is the zero address, 1 pending withdrawal per receiver
        if (pendingWithdrawals[receiver].next != address(0)) {
            revert PendingWithdrawalAddressErr();
        }

        // update pending withdrawals
        // new withdrawal inserted at the front of the list takes the current heads next address
        // can either be the head address `address(1)` if the list is empty, receiving its first element, or
        // if the list is not empty the next address of the current head
        pendingWithdrawals[receiver] = Withdrawal({
            next: pendingWithdrawals[head].next,
            amount: assets
        });
        // update head to point to the new withdrawal receiver address
        pendingWithdrawals[head].next = receiver;
        // update list size
        listSize++;
    }

    /**
     * @notice get list of withdrawals
     * @return withdrawals list of withdrawal structs
     */
    function getWithdrawals() public view returns (Withdrawal[] memory) {
        Withdrawal[] memory withdrawals = new Withdrawal[](listSize);
        address current = pendingWithdrawals[head].next;
        for (uint256 i = 0; i < listSize; i++) {
            withdrawals[i] = current;
            current = pendingWithdrawals[current].next;
        }
        return withdrawals;
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
     * @notice complete pending withdrawal
     */
    function completeWithdrawal() external {
        if (msg.sender != fundOperator) revert OnlyFundOperator();
        if (listSize == 0) revert NoPendingWithdrawals();
        // get address from head.next
        address receiver = pendingWithdrawals[head].next;
        // get amount from receiver
        uint256 amount = pendingWithdrawals[receiver].amount;
        // update pending withdrawals and clear space once completed
        pendingWithdrawals[head].next = pendingWithdrawals[receiver].next;
        // update list size
        listSize--;
        // transfer assets to receiver
        asset.safeTransfer(receiver, amount);
        // update reserves
        usdcReserves -= amount;
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
     * @param _operateProcedures array of operations to execute on RYSK/OPYN
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

                    // parse into RYSK ActionArgs
                    RyskActions.ActionArgs memory ryskAction = CombinedActions._parseRyskArgs(_operateProcedures[i].operationQueue[j]);

                    // ISSUE (0)
                    if (ryskAction.actionType == RyskActions.ActionType.Issue) {
                        // load option series
                        Types.OptionSeries memory optionSeries = ryskAction.optionSeries;

                        // check option series expiration is not more than 30 days in the future
                        if (optionSeries.expiration > block.timestamp + 30 days) {
                            revert InvalidOperation();
                        }

                        // more safety checks here (WIP)
                        int256 netDhv = IAlphaPortfolioValuesFeed(alphaPortfolioValuesFeed).netDhvExposure(oHash);


                        // measure slippage from beyondpricer, assert slippage tolerance
                        (uint256 totalPremium, int256 totalDelta, uint256 totalFees) = 
                            beyondPricer.quoteOptionPrice(
                                ryskAction.optionSeries, 
                                ryskAction.amount, 
                                optionSeries.isPut,
                                netDhv
                            );

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