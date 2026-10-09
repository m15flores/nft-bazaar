// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

import "../../src/NFTBazaar.sol";

contract NFTBazaarHarness is NFTBazaar {

    constructor(address feeRecipient_, uint16 feeBps_) NFTBazaar(feeRecipient_, feeBps_) {}

    function computeSplit(address nft_, uint256 tokenId_, uint256 price_) external view returns (uint256 fee, address royaltyReceiver, uint256 royalty, uint256 proceeds) {
        return _computeSplit(nft_, tokenId_, price_);
    }

    function settle(address nft_, uint256 tokenId_, address seller_, address buyer_, address paymentToken_, uint256 price_) external payable {
        _settle(nft_, tokenId_, seller_, buyer_, paymentToken_, price_);
    }
}