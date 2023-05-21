pragma solidity ^0.8.19;

import { ERC20 } from "solmate/tokens/ERC20.sol";

contract MockERC20 is ERC20 {

    constructor() ERC20("Mock Token", "MOCK", 18) {}

    function mint(uint256 _amount) public {
        super.mint(_amount);
    }

    function burn(uint256 _amount) public {
        super.burn(_amount);
    }
}