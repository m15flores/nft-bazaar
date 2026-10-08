// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {MockERC721} from "./MockERC721.sol";

/// @dev Returns whatever royalty it is told to, regardless of the sale price
contract MockERC721CustomRoyalty is MockERC721 {
    address public royaltyReceiver;
    uint256 public royaltyAmount;

    function setRoyalty(address receiver_, uint256 amount_) external {
        royaltyReceiver = receiver_;
        royaltyAmount = amount_;
    }

    function royaltyInfo(uint256, uint256) external view returns (address, uint256) {
        return (royaltyReceiver, royaltyAmount);
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IERC2981).interfaceId || super.supportsInterface(interfaceId);
    }
}