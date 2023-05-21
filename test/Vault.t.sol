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

import { Minter } from "./Minter.sol";
import { MockERC20 } from "./Mocks/MockERC20.sol";

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
    MockERC20 public USDC;

    // vault
    Vault vault;

    function setUp() external {
        USDC = MockERC20(0x408c5755b5c7a0a28D851558eA3636CfC5b5b19d);
        controller = IController(0x8e3e84E7F207b0b66BD8D902C293cF269C67a168);
        optionExchange = IOptionExchange(0xb672fE86693bF6f3b034730f5d2C77C8844d6b45);
        optionRegistry = IOptionRegistry(0x4E89cc3215AF050Ceb63Ca62470eeC7C1A66F737);
        liquidityPool = ILiquidityPool(0x0B1Bf5fb77AA36cD48Baa1395Bc2B5fa0f135d8C);

        // deploy vault
        vault = new Vault(
            USDC,
            controller,
            address(optionExchange),
            address(optionRegistry),
            address(liquidityPool)
        );

        vm.deal(address(this), 100 ether);
        Minter.mintUSDCL2(address(this), 10 ** 36, address(USDC));
        USDC.approve(address(vault), type(uint256).max);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*               ERC4626 deposit/withdrawal                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    // HommVault deposit USDC => HOMM
    function testDeposit() external {
        emit log_named_uint("HOMM Balance of depositor BEFORE:", vault.balanceOf(address(this)));
        emit log_named_uint("USDC Balance of depositor BEFORE:", USDC.balanceOf(address(this)));
        emit log_named_uint("HOMM Balance of Vault BEFORE:", vault.balanceOf(address(vault)));
        emit log_named_uint("USDC Balance of Vault BEFORE:", USDC.balanceOf(address(vault)));

        // mint vault shares
        uint256 shareAmount = vault.deposit(10 ** 36, address(this));

        emit log_named_uint("Deposit Share Output AFTER:", shareAmount);
        emit log_named_uint("HOMM Balance of depositer AFTER:", vault.balanceOf(address(this)));
        emit log_named_uint("USDC Balance of depositor AFTER:", USDC.balanceOf(address(this)));
        emit log_named_uint("HOMM Balance of Vault AFTER:", vault.balanceOf(address(vault)));
        emit log_named_uint("USDC Balance of Vault AFTER:", USDC.balanceOf(address(vault)));

        assertEq(vault.totalAssets(), 10 ** 36);
        assertEq(shareAmount, 0);
        assertEq(0, vault.balanceOf(address(vault)));
    }

    // Mint HOMM using USDC
    function testMint() external {
        emit log_named_uint("HOMM Balance of depositor BEFORE:", vault.balanceOf(address(this)));
        emit log_named_uint("USDC Balance of depositor BEFORE:", USDC.balanceOf(address(this)));
        emit log_named_uint("HOMM Balance of Vault BEFORE:", vault.balanceOf(address(vault)));
        emit log_named_uint("USDC Balance of Vault BEFORE:", USDC.balanceOf(address(vault)));

        // mint vault shares
        uint256 assetAmount = vault.mint(10 ** 36, address(this));

        emit log_named_uint("Deposit Share Output AFTER:", assetAmount);
        emit log_named_uint("HOMM Balance of depositer AFTER:", vault.balanceOf(address(this)));
        emit log_named_uint("USDC Balance of depositor AFTER:", USDC.balanceOf(address(this)));
        emit log_named_uint("HOMM Balance of Vault AFTER:", vault.balanceOf(address(vault)));
        emit log_named_uint("USDC Balance of Vault AFTER:", USDC.balanceOf(address(vault)));

        assertEq(vault.totalAssets(), 10 ** 36);
        assertEq(assetAmount, 0);
        assertEq(0, vault.balanceOf(address(vault)));
    }

    // HommVault withdraw HOMM => USDC
    function testWithdraw() external {
        _preLoadDeposit(10 ** 36, address(this));

        uint256 sum = vault.balanceOf(address(this)) + USDC.balanceOf(address(this)); 
        emit log_named_uint("HOMM Balance of depositor BEFORE:", vault.balanceOf(address(this)));
        emit log_named_uint("HOMM Balance of Vault BEFORE:", vault.balanceOf(address(vault)));
        emit log_named_uint("USDC Balance of depositor BEFORE:", USDC.balanceOf(address(this)));
        emit log_named_uint("USDC Balance of Vault BEFORE:", USDC.balanceOf(address(vault)));

        // withdraw/burn HOMM for USDC
        uint256 shareAmount = vault.withdraw(10 ** 36, address(this), address(this));

        emit log_named_uint("Withdraw Share Output AFTER:", shareAmount);
        emit log_named_uint("HOMM Balance of depositer AFTER:", vault.balanceOf(address(this)));
        emit log_named_uint("HOMM Balance of Vault AFTER:", vault.balanceOf(address(vault)));
        emit log_named_uint("USDC Balance of depositor AFTER:", USDC.balanceOf(address(this)));
        emit log_named_uint("USDC Balance of Vault AFTER:", USDC.balanceOf(address(vault)));

        assertEq(shareAmount, 0);
        assertEq(USDC.balanceOf(address(this)), sum);
        assertEq(vault.totalAssets(), 0);
    }

    // Redeem HOMM using USDC
    function testRedeem() external {
        _preLoadMint(10 ** 36, address(this));
        uint256 sum = vault.balanceOf(address(this)) + USDC.balanceOf(address(this));
        emit log_named_uint("HOMM Balance of depositor BEFORE:", vault.balanceOf(address(this)));
        emit log_named_uint("HOMM Balance of Vault BEFORE:", vault.balanceOf(address(vault)));
        emit log_named_uint("USDC Balance of depositor BEFORE:", USDC.balanceOf(address(this)));
        emit log_named_uint("USDC Balance of Vault BEFORE:", USDC.balanceOf(address(vault)));

        // withdraw/burn HOMM for USDC
        uint256 assetAmount = vault.redeem(10 ** 36, address(this), address(this));

        emit log_named_uint("Withdraw Share Output AFTER:", assetAmount);
        emit log_named_uint("HOMM Balance of depositer AFTER:", vault.balanceOf(address(this)));
        emit log_named_uint("HOMM Balance of Vault AFTER:", vault.balanceOf(address(vault)));
        emit log_named_uint("USDC Balance of depositor AFTER:", USDC.balanceOf(address(this)));
        emit log_named_uint("USDC Balance of Vault AFTER:", USDC.balanceOf(address(vault)));

        assertEq(sum, USDC.balanceOf(address(this)));
        assertEq(vault.totalAssets(), 0);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       TIME TEST                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function testEpochs() external {
        vm.warp(1684653734 + 3 days);
        vm.expectRevert();
        vault.mint(10 ** 36, address(this));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    OPERATOR TESTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function operatorDepositLiquidity() external {
        emit log_named_uint("HOMM Balance of depositor BEFORE:", vault.balanceOf(address(this)));
        emit log_named_uint("HOMM Balance of Vault BEFORE:", vault.balanceOf(address(vault)));
        emit log_named_uint("USDC Balance of depositor BEFORE:", USDC.balanceOf(address(this)));
        emit log_named_uint("USDC Balance of Vault BEFORE:", USDC.balanceOf(address(vault)));

        vault.depositLiquidity(10 ** 36);

        emit log_named_uint("HOMM Balance of depositer AFTER:", vault.balanceOf(address(this)));
        emit log_named_uint("HOMM Balance of Vault AFTER:", vault.balanceOf(address(vault)));
        emit log_named_uint("USDC Balance of depositor AFTER:", USDC.balanceOf(address(this)));
        emit log_named_uint("USDC Balance of Vault AFTER:", USDC.balanceOf(address(vault)));

        assertEq(vault.totalAssets(), USDC.balanceOf(address(vault)));
    }

    function testInitiateWithdraw() external {
        _preLoadDeposit(10 ** 36, address(this));

        emit log_named_uint("HOMM Balance of depositor BEFORE:", vault.balanceOf(address(this)));
        emit log_named_uint("HOMM Balance of Vault BEFORE:", vault.balanceOf(address(vault)));
        emit log_named_uint("USDC Balance of depositor BEFORE:", USDC.balanceOf(address(this)));
        emit log_named_uint("USDC Balance of Vault BEFORE:", USDC.balanceOf(address(vault)));

        // withdraw/burn HOMM for USDC
        vault.initiateWithdraw(10 ** 36);

        emit log_named_uint("HOMM Balance of depositer AFTER:", vault.balanceOf(address(this)));
        emit log_named_uint("HOMM Balance of Vault AFTER:", vault.balanceOf(address(vault)));
        emit log_named_uint("USDC Balance of depositor AFTER:", USDC.balanceOf(address(this)));
        emit log_named_uint("USDC Balance of Vault AFTER:", USDC.balanceOf(address(vault)));
    }

    function testTradeSimple() external {
        
    }



    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        HELPERS                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _preLoadDeposit(uint256 _amount, address _receiver) internal returns (uint256 shareAmount) {
        mintUSDCL2(_receiver, _amount, address(USDC));

        // approve vault to spend USDC
        USDC.approve(address(vault), type(uint256).max);

        // mint vault shares
        uint256 shareAmount = vault.deposit(_amount, address(this));
    }

    function _preLoadMint(uint256 _amount, address _receiver) internal returns (uint256 assetAmount) {
        mintUSDCL2(_receiver, _amount, address(USDC));

        // approve vault to spend USDC
        USDC.approve(address(vault), type(uint256).max);

        // mint vault shares
        uint256 shareAmount = vault.deposit(_amount, address(this));
    }

}