// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "../../src/NFTBazaar.sol";

contract ReentrantWithdrawer {
    NFTBazaar public immutable bazaar;
    uint256 public reentries;

    constructor(NFTBazaar bazaar_) {
        bazaar = bazaar_;
    }

    function attack() external {
        bazaar.withdraw();
    }

    receive() external payable {
        if (reentries < 5) {
            reentries++;
            bazaar.withdraw();
        }
    }
}
