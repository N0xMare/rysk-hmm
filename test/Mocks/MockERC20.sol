pragma solidity ^0.8.19;

import { ERC20 } from "solmate/tokens/ERC20.sol";

contract MockERC20 is ERC20 {

    constructor() ERC20("ERC20Mock", "E20M", 18) {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external {
        _burn(account, amount);
    }
}