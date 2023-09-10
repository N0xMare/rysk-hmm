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
     * @notice initiate burning vault shares to sends "assets" (USDC) of underlying tokens to "receiver".
     * @param shares amount of "shares" to burn
     * @param receiver address to send "assets" (USDC) to
     */
    function initiateWithdraw(uint256 shares, address receiver) public nonReentrant {
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
    /// NOTE: no execution checks, depositors trust the fund operator entirely to reimburse and
    ///       behave in expected ways as no contract level assertions have been made
    function execute(IOptionExchange.OperationProcedures[] memory _operateProcedures) external {
        if (msg.sender != fundOperator) revert OnlyFundOperator();
        // OptionExchange.operate()
        IOptionExchange(optionExchange).operate(_operateProcedures);
        // increment executionNonce
        executionNonce++;
        emit Execute(executionNonce, _operateProcedures);
    }

    /**
     * @notice create an option token on rysk
     * @param _optionSeries option series for the o token being created
     * @return seriesAddress address of the option token
     */
    function createOptionToken(Types.OptionSeries memory _optionSeries) external returns (address seriesAddress) {
        seriesAddress = IOptionExchange(optionExchange).createOtoken(_optionSeries);
    }

    /// @notice OptionRegistry ///////////////////////////////////

    /**
     * @notice redeem option series on Rysk
     * @param _series the address of the option token to be burnt and redeemed
     * @return amount of underlying asset amount returned
     */
    function redeemOptionToken(address _series) public returns (uint256) {
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