// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console2.sol";

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
    address public usdc = 0x408c5755b5c7a0a28D851558eA3636CfC5b5b19d;

    // rysk & opyn contracts
    IController public controller;
    IOptionExchange public optionExchange;
    IOptionRegistry public optionRegistry;
    ILiquidityPool public liquidityPool;

    // vault
    Vault vault;

    function setUp() external {

        setRyskContracts();

        // deploy vault
        vault = new Vault(
            controller,
            usdc,
            address(optionExchange),
            address(optionRegistry),
            address(liquidityPool)
        );

    }

    function setRyskContracts() external {
        controller = IController(0x8e3e84E7F207b0b66BD8D902C293cF269C67a168);
        optionExchange = IOptionExchange(0x39246c4f3F6592C974ebc44F80ba6dc69B817C71);
        optionRegistry = IOptionRegistry(0x7F4B2A690605A7cbb66F7AA6885EbD906a5e2E9E);
        liquidityPool = ILiquidityPool(0xEd6BcbF6907D4feEEe8a8875543249bEa9D308E8);
    }

    // VM Cheatcodes can be found in ./lib/forge-std/src/Vm.sol
    // Or at https://github.com/foundry-rs/forge-std
    function testCalls() external {
        
    }
}