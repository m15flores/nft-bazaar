// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Royalty.sol";

contract MockERC721Royalty is ERC721Royalty {
    constructor() ERC721("MockNFT", "MNFT") {}

    function mint(address to_, uint256 tokenId_) external {
        _mint(to_, tokenId_);
    }

    function setDefaultRoyalty(address receiver_, uint96 feeBps_) external {
        _setDefaultRoyalty(receiver_, feeBps_);
    }
}