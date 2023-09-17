// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console2.sol";
import "solmate/tokens/ERC20.sol";

// contracts
import { Vault } from "../src/Vault.sol";
import { IController } from "../src/interfaces/IGammaInterface.sol";
import { ILiquidityPool } from "../src/interfaces/ILiquidityPool.sol";
import { IOptionExchange } from "../src/interfaces/IOptionExchange.sol";
import { IOptionRegistry } from "../src/interfaces/IOptionRegistry.sol";
import { IBeyondPricer } from "../src/interfaces/IBeyondPricer.sol";

import { Minter } from "./Minter.sol";
import { MockERC20 } from "./Mocks/MockERC20.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";

contract VaultTest is Test, Minter {
    using stdStorage for StdStorage;

    // environment
    // fund operator = address(this)

    // RPC (Abitrum Goerli)
    //string RPC_ARB_GOERLI = vm.envString("ARBI_GOERLI_RPC_URL");

    // asset (underlying vault asset, arb goerli rysk USDC)

    // rysk & opyn contracts
    IController public controller;
    IOptionExchange public optionExchange;
    IOptionRegistry public optionRegistry;
    ILiquidityPool public liquidityPool;
    IBeyondPricer public beyondPricer;
    MockERC20 public underlying;

    // vault
    Vault vault;

    function setUp() external {
        underlying = MockERC20(0x408c5755b5c7a0a28D851558eA3636CfC5b5b19d);
        controller = IController(0x8e3e84E7F207b0b66BD8D902C293cF269C67a168);
        optionExchange = IOptionExchange(0xb672fE86693bF6f3b034730f5d2C77C8844d6b45);
        optionRegistry = IOptionRegistry(0x4E89cc3215AF050Ceb63Ca62470eeC7C1A66F737);
        liquidityPool = ILiquidityPool(0x0B1Bf5fb77AA36cD48Baa1395Bc2B5fa0f135d8C);
        beyondPricer = IBeyondPricer(0xc939df369C0Fc240C975A6dEEEE77d87bCFaC259);

        // deploy vault
        vault = new Vault(
            underlying,
            address(controller),
            address(optionExchange),
            address(optionRegistry),
            address(liquidityPool),
            address(beyondPricer)
        );

        vm.deal(address(this), 100 ether);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*               ERC4626 deposit/withdrawal                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    // deposit USDC => VaultShares
    function testDepositSimple() external {
        emit log_named_uint("VaultShare Balance of depositor BEFORE", vault.balanceOf(address(this)));          // 0
        emit log_named_uint("USDC Balance of depositor BEFORE", underlying.balanceOf(address(this)));     // 1000 1e18
        emit log_named_uint("VaultShare Balance of Vault BEFORE", vault.balanceOf(address(vault)));             // 0
        emit log_named_uint("USDC Balance of Vault BEFORE", underlying.balanceOf(address(vault)));        // 0
        emit log_named_uint("Total Assets of Vault BEFORE", vault.totalAssets());                         // 0

        // mint usdc and approve vault to spend
        Minter.mintUSDCL2(address(this), 10 ** 26, address(underlying));
        underlying.approve(address(vault), type(uint256).max);

        // mint vault shares
        uint256 shareAmount = vault.deposit(10 ** 26, address(this));

        emit log_named_uint("Deposit Share Output AFTER", shareAmount);                                   // 1e26
        emit log_named_uint("VaultShare Balance of depositer AFTER", vault.balanceOf(address(this)));           // 1e26
        emit log_named_uint("USDC Balance of depositor AFTER", underlying.balanceOf(address(this)));      // 0
        emit log_named_uint("VaultShare Balance of Vault AFTER", vault.balanceOf(address(vault)));              // 0
        emit log_named_uint("USDC Balance of Vault AFTER", underlying.balanceOf(address(vault)));         // 1e26
        emit log_named_uint("Total Assets of Vault AFTER", vault.totalAssets());                          // 1e26

        // total assets should be equal to vault balance of collateral asset always
        assertEq(vault.totalAssets(), underlying.balanceOf(address(vault)));
        // vault balance of collateral asset should be equal to the amount deposited
        assertEq(underlying.balanceOf(address(vault)), 10 ** 26);
        // shares minted should be equal to the amount deposited
        assertEq(shareAmount, vault.balanceOf(address(this)));
        // vault balance of VaultShare should be 0
        assertEq(vault.balanceOf(address(vault)), 0);
    }


    /// @notice from solmate test suite
    function testMultipleDepositRedeem() public {
        address alice = address(0xABCD);
        address bob = address(0xDCBA);

        uint256 mutationUnderlyingAmount = 3000;

        Minter.mintUSDCL2(alice, 4000, address(underlying));

        vm.prank(alice);
        underlying.approve(address(vault), 4000);

        assertEq(underlying.allowance(alice, address(vault)), 4000);

        Minter.mintUSDCL2(bob, 7001, address(underlying));

        vm.prank(bob);
        underlying.approve(address(vault), 7001);

        assertEq(underlying.allowance(bob, address(vault)), 7001);

        // 1. Alice deposits 2000 assets
        vm.prank(alice);
        uint256 aliceSharesOutputAmount = vault.deposit(2000, alice);

        uint256 aliceSharePreviewAmount = vault.previewDeposit(vault.convertToAssets(aliceSharesOutputAmount));

        // Expect to have received the requested mint amount.
        assertEq(aliceSharePreviewAmount, 2000);
        assertEq(vault.balanceOf(alice), aliceSharePreviewAmount);
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), vault.convertToAssets(aliceSharesOutputAmount));
        assertEq(aliceSharesOutputAmount, vault.balanceOf(alice));

        // Expect a 1:1 ratio before mutation.
        assertEq(vault.convertToAssets(aliceSharesOutputAmount), 2000);

        // Sanity check.
        assertEq(vault.totalSupply(), aliceSharePreviewAmount);
        assertEq(vault.totalAssets(), vault.convertToAssets(aliceSharesOutputAmount));

        // 2. Bob deposits 4000 tokens (mints 4000 shares)
        vm.prank(bob);
        uint256 bobShareAmount = vault.deposit(4000, bob);
        uint256 bobUnderlyingAmount = vault.previewRedeem(bobShareAmount);

        // Expect to have received the requested underlying amount.
        assertEq(bobUnderlyingAmount, 4000);
        assertEq(vault.balanceOf(bob), bobShareAmount);
        assertEq(vault.convertToAssets(vault.balanceOf(bob)), bobUnderlyingAmount);
        assertEq(vault.convertToShares(bobUnderlyingAmount), vault.balanceOf(bob));

        // Expect a 1:1 ratio before mutation.
        assertEq(bobShareAmount, bobUnderlyingAmount);

        // Sanity check.
        uint256 preMutationShareBal = aliceSharePreviewAmount + bobShareAmount;
        uint256 preMutationBal = vault.convertToAssets(aliceSharesOutputAmount) + bobUnderlyingAmount;
        assertEq(vault.totalSupply(), preMutationShareBal);
        assertEq(vault.totalAssets(), preMutationBal);
        assertEq(vault.totalSupply(), 6000);
        assertEq(vault.totalAssets(), 6000);

        // 3. Vault mutates by +3000 tokens...                    |
        //    (simulated yield returned from strategy)...
        // The Vault now contains more tokens than deposited which causes the exchange rate to change.
        // Alice share is 33.33% of the Vault, Bob 66.66% of the Vault.
        // Alice's share count stays the same but the underlying amount changes from 2000 to 3000.
        // Bob's share count stays the same but the underlying amount changes from 4000 to 6000.
        Minter.mintUSDCL2(address(vault), mutationUnderlyingAmount, address(underlying));

        assertEq(vault.totalSupply(), preMutationShareBal);
        assertEq(vault.totalAssets(), preMutationBal + mutationUnderlyingAmount);
        assertEq(vault.balanceOf(alice), aliceSharePreviewAmount);
        assertEq(
            vault.convertToAssets(vault.balanceOf(alice)),
            aliceSharesOutputAmount + (mutationUnderlyingAmount / 3) * 1
        );
        
        assertEq(vault.balanceOf(bob), bobShareAmount);
        assertEq(vault.convertToAssets(vault.balanceOf(bob)), bobUnderlyingAmount + (mutationUnderlyingAmount / 3) * 2);

        // 4. Alice deposits 2000 tokens (mints 1333 shares)
        vm.prank(alice);
        vault.deposit(2000, alice);

        assertEq(vault.totalSupply(), 7333);
        assertEq(vault.balanceOf(alice), 3333);
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), 4999);
        assertEq(vault.balanceOf(bob), 4000);
        assertEq(vault.convertToAssets(vault.balanceOf(bob)), 6000);

        // 5. Bob deposits with 2000 assets
        // NOTE: Bob's assets spent got rounded up
        // NOTE: Alices's vault assets got rounded up
        vm.prank(bob);
        vault.deposit(3001, bob);

        assertEq(vault.totalSupply(), 9333);
        assertEq(vault.balanceOf(alice), 3333);
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), 5000);
        assertEq(vault.balanceOf(bob), 6000);
        assertEq(vault.convertToAssets(vault.balanceOf(bob)), 9000);

        // Sanity checks:
        // Alice and bob should have spent all their tokens now
        assertEq(underlying.balanceOf(alice), 0);
        assertEq(underlying.balanceOf(bob), 0);
        // Assets in vault: 4k (alice) + 7k (bob) + 3k (yield) + 1 (round up)
        assertEq(vault.totalAssets(), 14001);

        // 6. Vault mutates by +3000 tokens
        // NOTE: Vault holds 17001 tokens, but sum of assetsOf() is 17000.
        Minter.mintUSDCL2(address(vault), mutationUnderlyingAmount, address(underlying));
        assertEq(vault.totalAssets(), 17001);
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), 6071);
        assertEq(vault.convertToAssets(vault.balanceOf(bob)), 10929);

        // 7. Alice intiates a withdraw of 1333 shares (2428 assets)
        vm.prank(alice);
        vault.initiateWithdraw(1333, alice);

        {
            // check alice's pending withdrawal
            (uint256 requestedSharesAmountOut, address owner, address next) 
                = vault.pendingWithdrawals(alice);

            // pending withdraw has correct amount of shares
            assertEq(requestedSharesAmountOut, 1333);
            // pending withdraw has correct owner
            assertEq(owner, alice);
            // pending withdraw has correct next address, only 1 active withdraw so next should be the head of the list
            assertEq(next, address(1));
        }

        // fund operator, address(this), completes alice's withdraw
        vault.completeWithdrawal();

        assertEq(underlying.balanceOf(alice), 2428);
        assertEq(vault.totalSupply(), 8000);
        assertEq(vault.totalAssets(), 14573);
        assertEq(vault.balanceOf(alice), 2000);
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), 3643);
        assertEq(vault.balanceOf(bob), 6000);
        assertEq(vault.convertToAssets(vault.balanceOf(bob)), 10929);

        // 8. Bob withdraws 2929 shares (5335 assets)
        vm.prank(bob);
        vault.initiateWithdraw(2929, bob);

        {
            // check bob's pending withdrawal
            (uint256 requestedSharesAmountOut, address owner, address next) 
                = vault.pendingWithdrawals(bob);
            // pending withdraw has correct amount of shares
            assertEq(requestedSharesAmountOut, 2929);
            // pending withdraw has correct owner
            assertEq(owner, bob);
            // pending withdraw has correct next address, only 1 active withdraw so next should be the head of the list
            assertEq(next, address(1));
        }

        // fund operator, address(this), completes bob's withdraw
        vault.completeWithdrawal();

        // assets(2929 shares) = 5335
        assertEq(underlying.balanceOf(bob), vault.convertToAssets(2929));
        assertEq(vault.totalSupply(), 5071);
        // 14573 - 5335 = 9238
        assertEq(vault.totalAssets(), 9238);
        assertEq(vault.balanceOf(alice), 2000);
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), 3643);
        // 6000 - 2929 = 3071
        assertEq(vault.balanceOf(bob), 3071);
        // assets(3071 shares) | 9238-3643 = 5594 (1 wei rounding off)
        assertEq(vault.convertToAssets(vault.balanceOf(bob)), 5594);

        // 9. Alice initiates withdraws of 2000 shares (3643 assets), last of her shares
        // NOTE: Bob's assets have been rounded back up
        vm.prank(alice);
        vault.initiateWithdraw(2000, alice);

        {
            // check alice's pending withdrawal
            (uint256 requestedSharesAmountOut, address owner, address next) 
                = vault.pendingWithdrawals(alice);
            // pending withdraw has correct amount of shares
            assertEq(requestedSharesAmountOut, 2000);
            // pending withdraw has correct owner
            assertEq(owner, alice);
            // pending withdraw has correct next address, only 1 active withdraw so next should be the head of the list
            assertEq(next, address(1));
        }

        // 10. Bob redeem 3071 shares (5594 assets), last of his shares
        vm.prank(bob);
        vault.initiateWithdraw(3071, bob);

        {
            // check bob's pending withdrawal
            (uint256 requestedSharesAmountOut, address owner, address next) 
                = vault.pendingWithdrawals(bob);
            // pending withdraw has correct amount of shares
            assertEq(requestedSharesAmountOut, 3071);
            // pending withdraw has correct owner
            assertEq(owner, bob);
            // pending withdraw has correct next address, 2 active withdraws so next should be the 
            // address before which is alice's withdraw
            assertEq(next, alice);
        }

        // 11. multi withdraw scenario

        // fund operator completes 1st withdraw request, bob's, since he was the lastest to initiate a withdraw
        vault.completeWithdrawal();

        assertEq(underlying.balanceOf(bob), 10929);
        assertEq(vault.totalSupply(), 2000);
        assertEq(vault.totalAssets(), 3644); // 3643 + 1 wei rounding leftover from bob's completed withdraw
        assertEq(vault.balanceOf(alice), 2000);
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), 3644); // 3643 + 1 wei
        assertEq(vault.balanceOf(bob), 0);
        assertEq(vault.convertToAssets(vault.balanceOf(bob)), 0);

        // fund operator completes 2nd withdraw request, alice's, since she was the first to initiate a withdraw
        vault.completeWithdrawal();

        assertEq(underlying.balanceOf(alice), 6072);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), 0);
        assertEq(vault.balanceOf(bob), 0);
        assertEq(vault.convertToAssets(vault.balanceOf(bob)), 0);

        // Sanity check
        assertEq(underlying.balanceOf(address(vault)), 0);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    OPERATOR TESTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// test setFundOperator
    function testSetFundOperator() external {
        // set fund operator to address(this)
        vault.setFundOperator(address(0xbeef));
        assertEq(vault.fundOperator(), address(0xbeef));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        HELPERS                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

}