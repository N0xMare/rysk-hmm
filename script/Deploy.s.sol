// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import "solmate/tokens/ERC20.sol";

import { Vault } from "../src/Vault.sol";
import { IController } from "../src/interfaces/IGammaInterface.sol";
import { ILiquidityPool } from "../src/interfaces/ILiquidityPool.sol";
import { IOptionExchange } from "../src/interfaces/IOptionExchange.sol";
import { IOptionRegistry } from "../src/interfaces/IOptionRegistry.sol";
import { IBeyondPricer } from "../src/interfaces/IBeyondPricer.sol";
import { Types } from "../src/libraries/Types.sol";


contract Deploy is Script {
    /// Deploy v1
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_KEY");
        string memory rpc = vm.envString("RPC_URL");

        vm.createSelectFork(rpc);
        vm.startBroadcast(deployerPrivateKey);

        // Deploy Vault
        Vault vault = new Vault(
            ERC20(0xaf88d065e77c8cC2239327C5EDb3A432268e5831),    // arb main-net USDC
            address(0xC820739fEdF9A28bE29f73c29E167f0c14F1FE2a),  // arb main-net Controller
            address(0xC117bf3103bd09552F9a721F0B8Bce9843aaE1fa),  // arb main-net OptionExchange
            address(0x8Bc23878981a207860bA4B185fD065f4fd3c7725),  // arb main-net OptionRegistry
            address(0x217749d9017cB87712654422a1F5856AAA147b80),  // arb main-net LiquidityPool
            address(0xeA5Fb118862876f249Ff0b3e7fb25fEb38158def)   // arb main-net BeyondPricer
        );

        vm.stopBroadcast();
    }
}