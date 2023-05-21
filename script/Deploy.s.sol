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


contract DeployAMM is Script {
    string RPC_URL;

    /// Deploy v1
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_KEY");
        string rpc = vm.envString("ARBI_GOERLI_RPC_URL");

        vm.createSelectFork(rpc);
        vm.startBroadcast(deployerPrivateKey);

        // Deploy Vault
        Vault vault = new Vault(
            ERC20(0x408c5755b5c7a0a28D851558eA3636CfC5b5b19d),       // USDC
            IController(0x8e3e84E7F207b0b66BD8D902C293cF269C67a168), // Controller
            address(0xb672fE86693bF6f3b034730f5d2C77C8844d6b45),     // OptionExchange
            address(0x4E89cc3215AF050Ceb63Ca62470eeC7C1A66F737),     // OptionRegistry
            address(0x0B1Bf5fb77AA36cD48Baa1395Bc2B5fa0f135d8C)      // LiquidityPool
        );

        vm.stopBroadcast();
    }
}