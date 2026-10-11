// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mimics USDC/USDT: transfers revert if sender or receiver is blacklisted.
contract MockERC20Blacklist is ERC20 {
    mapping(address => bool) public blacklisted;

    error Blacklisted(address account);

    constructor() ERC20("Blacklist Token", "BLK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setBlacklisted(address account, bool value) external {
        blacklisted[account] = value;
    }

    function _update(address from, address to, uint256 value) internal override {
        if (blacklisted[from]) revert Blacklisted(from);
        if (blacklisted[to]) revert Blacklisted(to);
        super._update(from, to, value);
    }
}
