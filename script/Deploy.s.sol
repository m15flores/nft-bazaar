// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "forge-std/Script.sol";
import "../src/NFTBazaar.sol";
import "../test/mocks/MockERC721Royalty.sol";

contract Deploy is Script {
    function run() external {
        address feeRecipient_ = vm.envAddress("FEE_RECIPIENT");
        address creator_ = vm.envAddress("CREATOR");

        vm.startBroadcast();
        NFTBazaar bazaar_ = new NFTBazaar(feeRecipient_, 250);
        MockERC721Royalty nft_ = new MockERC721Royalty();
        nft_.setDefaultRoyalty(creator_, 500);
        vm.stopBroadcast();

        console.log("NFTBazaar:", address(bazaar_));
        console.log("Collection:", address(nft_));
    }
}
