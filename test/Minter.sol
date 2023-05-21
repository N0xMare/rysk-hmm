// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

interface USDL2 {
    // FOR USDC
    function mint(address to, uint256 amount) external;
    function bridgeMint(address, uint256) external;
    function gatewayAddress() external view returns (address);
}

contract Minter is Test {
    function mintUSDCL2(address _to, uint256 _amount, address _token) public {
        USDL2 USDC = USDL2(_token);
        // governor address on arb goerli
        vm.startBroadcast(0xF8F8E45A1f470E92D2B714EBf58b266AabBeD45D);
        USDC.mint(_to, _amount);
        vm.stopBroadcast();
    }
}