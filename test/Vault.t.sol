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

contract VaultTest is Test {
    using stdStorage for StdStorage;

    // environment
    // fund operator = address(this)

    // RPC (Abitrum Goerli)
    string RPC_ARB_GOERLI = vm.envString("ARBI_GOERLI_RPC_URL");

    // asset (underlying vault asset, arb goerli rysk USDC)

    // rysk & opyn contracts
    IController public controller;
    IOptionExchange public optionExchange;
    IOptionRegistry public optionRegistry;
    ILiquidityPool public liquidityPool;
    //ERC20 public USDC = ERC20(0x408c5755b5c7a0a28D851558eA3636CfC5b5b19d);
    ERC20 public MockERC20;

    // vault
    Vault vault;

    function setUp() external {

        controller = IController(0x8e3e84E7F207b0b66BD8D902C293cF269C67a168);
        optionExchange = IOptionExchange(0xb672fE86693bF6f3b034730f5d2C77C8844d6b45);
        optionRegistry = IOptionRegistry(0x4E89cc3215AF050Ceb63Ca62470eeC7C1A66F737);
        liquidityPool = ILiquidityPool(0x0B1Bf5fb77AA36cD48Baa1395Bc2B5fa0f135d8C);

        // deploy vault
        /*vault = new Vault(
            USDC,
            controller,
            address(optionExchange),
            address(optionRegistry),
            address(liquidityPool)
        );*/

        // assert operator set
        //assertEq(controller.isOperator(address(this), address(vault)), true);
    }

    function testCalls() external {
        
    }
}