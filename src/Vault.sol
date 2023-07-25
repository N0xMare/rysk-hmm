// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @notice solmate
import { ERC4626 } from "solmate/mixins/ERC4626.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "solmate/utils/FixedPointMathLib.sol";
import { ReentrancyGuard } from "solmate/utils/ReentrancyGuard.sol";

/// @notice rysk
// interfaces
import { ILiquidityPool } from "./interfaces/ILiquidityPool.sol";
import { IOptionExchange } from "./interfaces/IOptionExchange.sol";
import { IOptionRegistry } from "./interfaces/IOptionRegistry.sol";
import { IAccounting } from "./interfaces/IAccounting.sol";
import { IController } from "./interfaces/IGammaInterface.sol";
import { IBeyondPricer } from "./interfaces/IBeyondPricer.sol";
// libraries
import { Types } from "./libraries/Types.sol";
import { CombinedActions } from "./libraries/CombinedActions.sol";
import { RyskActions } from "./libraries/RyskActions.sol";

/// @notice Tokenized Vault for Rysk Options Market, Wheel Trading Strategy
contract Vault is ERC4626, ReentrancyGuard {
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
        uint256 indexed executionNonce, 
        IOptionExchange.OperationProcedures[] operationProcedures
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

    /// @notice Withdrawal struct
    // amount to withdraw for receiver
    // next receiver address
    struct Withdrawal {
        uint256 shareAmount;
        address owner;
        address next;
    }

    /// @notice reserves, USDC balance of this contract
    uint256 public usdcReserves;
    /// @notice active capital, USDC balance deployed in vault strategy managed by the operator
    uint256 public activeCapital;
    // NOTE: PnL calc, is checking difference between assets received back from trades with activeCapital amount we txs out of vault

    /// @notice pending withdrawals map (receiver => Withdrawal(amount, next_receiver_addr))
    // kinda like a linked list, but not really
    mapping(address => Withdrawal) public pendingWithdrawals;
    /// @notice pending withdrawals size
    uint256 public listSize;
    /// @notice pending withdrawals list head
    address constant head = address(1);
    /// @notice balances mapping
    mapping(address => uint256) public balances;

    /// @notice operator
    address public fundOperator;

    /// @notice operate() nonce
    uint256 public executionNonce;
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
    constructor(
        ERC20 _asset,
        address _controller,
        address _optionExchange,
        address _optionRegistry,
        address _liquidityPool,
        address _beyondPricer
        )
        ERC4626(_asset, "Rysk USDC Vault", "ryskUSDC")
        {
        // set fund operator
        fundOperator = msg.sender;
        optionExchange = _optionExchange;
        optionRegistry = _optionRegistry;
        liquidityPool = _liquidityPool;
        beyondPricer = _beyondPricer;
        // set optionExchange as operator in controller
        IController(_controller).setOperator(address(optionExchange), true);
        // initialize pending withdrawals
        pendingWithdrawals[head] = Withdrawal({shareAmount: 0, owner: head, next: head});
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
    function deposit(uint256 assets, address receiver) public override nonReentrant returns (uint256 shares) {
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
    function mint(uint256 shares, address receiver) public override nonReentrant returns (uint256 assets) {
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
    function initiateWithdraw(uint256 assets, address receiver) public nonReentrant {
        uint256 sharesWithdrawalAmount = convertToShares(assets);
        if (sharesWithdrawalAmount == 0) {
            revert InsufficientAmount();
        }
        // current share balance of msg.sender
        uint256 currentShares = this.balanceOf(msg.sender);
        // total number of assets from msg.sender's receiver pending withdrawals
        uint256 currentWithdrawAmount = pendingWithdrawals[receiver].shareAmount;

        // verify msg.sender has enough shares/assets for withdrawal
        // user cannot withdraw more than their total balance
        if (currentShares < sharesWithdrawalAmount) {
            revert WithdrawalAmountErr();
        }
        if (currentShares < currentWithdrawAmount + sharesWithdrawalAmount) {
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
            shareAmount: currentWithdrawAmount + sharesWithdrawalAmount,
            owner: msg.sender,
            next: pendingWithdrawals[head].next
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
    function initiateRedeem(uint256 shares, address receiver) public nonReentrant {
        if (shares == 0) {
            revert InsufficientAmount();
        }
        // assets amount to withdraw
        uint256 currentShares = this.balanceOf(msg.sender);
        // total number of assets from msg.sender's pending withdrawals
        uint256 currentWithdrawAmount = pendingWithdrawals[receiver].shareAmount;

        // user cannot withdraw more than their total balance
        if (currentShares < shares) {
            revert WithdrawalAmountErr();
        }
        if (currentShares < currentWithdrawAmount + shares) {
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
            shareAmount: currentShares + shares,
            owner: msg.sender,
            next: pendingWithdrawals[head].next
        });
        // update head to point to the new withdrawal receiver address
        pendingWithdrawals[head].next = receiver;
        // update list size
        listSize++;
    }

    /**
     * @notice get list of withdrawals
     * @return receivers array of receiver addresses with pending withdrawals
     * @return withdrawals array of Withdrawal structs for receivers with pending withdrawals
     */
    function getWithdrawals() public view returns (address[] memory receivers, Withdrawal[] memory withdrawals) {
        // define withdrawals array
        withdrawals = new Withdrawal[](listSize);
        // define receivers array
        receivers = new address[](listSize);
        // set current to front address
        address current = pendingWithdrawals[head].next;
        for (uint256 i = 0; i < listSize; i++) {
            // add current receiver and withdrawal to arrays
            receivers[i] = current;
            withdrawals[i] = pendingWithdrawals[current];
            // update current to next receiver
            current = pendingWithdrawals[current].next;
        }
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

    /// @notice Set Fund Operator
    /// @param _fundOperator address of the fund operator
    function setFundOperator(address _fundOperator) external {
        if (msg.sender != fundOperator) revert OnlyFundOperator();
        fundOperator = _fundOperator;
    }

    /// @notice Fund Withdrawal Functions //////////////////

    /**
     * @notice complete pending withdrawal
     */
    function completeWithdrawal() external nonReentrant {
        if (msg.sender != fundOperator) revert OnlyFundOperator();
        if (listSize == 0) revert NoPendingWithdrawals();
        // get receiver address from head.next
        address receiver = pendingWithdrawals[head].next;
        // get owner address from receiver
        address owner = pendingWithdrawals[receiver].owner;
        // get amount from receiver
        uint256 shares = pendingWithdrawals[receiver].shareAmount;
        // amount in assets to withdraw
        uint256 amountOutAssets = convertToAssets(shares);
        // update pending withdrawals and clear space once completed
        pendingWithdrawals[head].next = pendingWithdrawals[receiver].next;
        // update list size
        listSize--;
        // call redeem to burn "owner" shares
        redeem(shares, receiver, owner);
        // transfer shares converted to the amount in assets to receiver address
        asset.safeTransfer(receiver, amountOutAssets);
        // update underlying reserves
        usdcReserves -= amountOutAssets;
        emit WithdrawalCompleted(receiver, amountOutAssets);
    }

    /// @notice OptionExchange Functions ////////////////////////

    /**
     * @notice check operator's execute() params for each prodecure are valid
     * @param procedure CombinedActions.OperationProcedures struct used in calls to execute()
     * @return bool if the operation is valid
     * NOTE: only for rysk actions as of now (WIP)
     */
/*
    function checkProdecure(IOptionExchange.OperationProcedures memory procedure) internal view returns (bool) {
        // OPYN
        if (procedure.operation == CombinedActions.OperationType.OPYN) {
            // currently no checks for opyn operations
            return true;
        }
        // RYSK
        else if (procedure.operation == CombinedActions.OperationType.RYSK) {
            // iterate through operationQueue/each action (ActionArg) in the procedure
            for(uint256 i = 0; i < procedure.operationQueue.length; i++) {
                // load action args
                CombinedActions.ActionArgs memory actionArgs = procedure.operationQueue[i];
                // load option series
                Types.OptionSeries memory optionSeries = procedure.operationQueue[i].optionSeries;
                // check option series expiration is not more than 30 days in the future
                if (optionSeries.expiration > block.timestamp + 30 days) {
                    return false;
                }
                // ISSUE OPTION
                if (actionArgs.actionType == 0) {
                    // assertions needed for issue
                    // strike price needs to be 1e18
                    // WIP
                    return true;
                }
                // BUY OPTION
                else if (actionArgs.actionType == 1) {
                    // assertions needed for buying
                    // decimal convert strike price
                    (address series, Types.OptionSeries memory convertSeries, uint128 strikePrice) =
                        IOptionExchange(optionExchange).getOptionDetails(
                            optionSeries,
                        );

                    IOptionExchange(optionExchange).checkHash(
                        optionSeries,

                    );
                    // WIP
                    return true;
                }
                // SELL OPTION
                else if (actionArgs.actionType == 2) {
                    // assertions needed for selling
                    // WIP
                    return true;
                }
                // CLOSE OPTION
                else if (actionArgs.actionType == 3) {
                    // assertions needed for closing
                    // WIP
                    return true;
                }
                // INVALID ACTION TYPE
                else {
                    return false;
                }
            }
        }
    }
*/


    /** Struct specification for OperationProcedures
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
    ----------------------------------------------------------------
    */
    /**
     * @notice execute actions on Rysk (WIP)
     * @param _operateProcedures array of operations to execute on RYSK/OPYN
     */
    function execute(IOptionExchange.OperationProcedures[] memory _operateProcedures) external {
        if (msg.sender != fundOperator) revert OnlyFundOperator();

        // iterate through _operateProcedures to check validity
        //for(uint8 i = 0; i < _operateProcedures.length; i++) {
        //    // validate the vault operator is making valid operation(s)
        //    bool output = checkProdecure(_operateProcedures[i]);
        //    if (output == false) revert InvalidOperation();
        //}

        // OptionExchange.operate()
        IOptionExchange(optionExchange).operate(_operateProcedures);
        // increment executionNonce
        executionNonce++;
        emit Execute(executionNonce, _operateProcedures);
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