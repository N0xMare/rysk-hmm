// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console2.sol";

// contracts
import { Vault } from "../src/Vault.sol";

contract VaultTest is Test {
    using stdStorage for StdStorage;

    // environment
    // fund operator address

    // asset (USDC)
    //address public 

    // rysk contracts
    //ILiquidityPool public liquidityPool;
    //IOptionExchange public optionExchange;
    //IOptionRegistry public optionRegistry;

    // vault
    //Vault vault;



    function setUp() external {
        //vault = new Vault();
    }

    // VM Cheatcodes can be found in ./lib/forge-std/src/Vm.sol
    // Or at https://github.com/foundry-rs/forge-std
    function testCalls() external {
        
    }
}