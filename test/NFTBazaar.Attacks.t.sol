// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "forge-std/Test.sol";
import "../src/NFTBazaar.sol";
import "./mocks/MockERC721Royalty.sol";
import "./mocks/MockERC20Blacklist.sol";
import "./mocks/ReentrantBuyer.sol";
import "./mocks/ReentrantWithdrawer.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract NFTBazaarAttacksTest is Test {
    NFTBazaar bazaar;
    MockERC721Royalty royaltyNft;
    MockERC20Blacklist blToken;
    address deployer;
    address seller;
    address buyer;
    address feeRecipient;
    address royaltyReceiver;

    uint256 constant PRICE = 1 ether;
    uint16 constant INITIAL_FEE_BPS = 250;

    function setUp() public {
        deployer = makeAddr("deployer");
        seller = makeAddr("seller");
        buyer = makeAddr("buyer");
        feeRecipient = makeAddr("feeRecipient");
        royaltyReceiver = makeAddr("royaltyReceiver");

        royaltyNft = new MockERC721Royalty();
        royaltyNft.mint(seller, 1);
        royaltyNft.mint(seller, 2);

        vm.prank(deployer);
        bazaar = new NFTBazaar(feeRecipient, INITIAL_FEE_BPS);

        royaltyNft.setDefaultRoyalty(royaltyReceiver, 500);
        vm.deal(buyer, 100 ether);

        blToken = new MockERC20Blacklist();
        vm.prank(deployer);
        bazaar.setAllowedToken(address(blToken), true);
    }

    // Reentrancy

    function test_Attack_RevertWhen_BuyerReentersBuyNFT() public {
        _listEth(1);
        _listEth(2);
        ReentrantBuyer attacker_ = new ReentrantBuyer(bazaar, address(royaltyNft), 1, 2, PRICE);
        vm.deal(address(attacker_), 2 * PRICE);

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        attacker_.attack();

        assertEq(royaltyNft.ownerOf(1), seller);
        assertEq(royaltyNft.ownerOf(2), seller);
        assertEq(address(bazaar).balance, 0);
        assertEq(bazaar.pendingEth(seller), 0);
        assertEq(bazaar.pendingEth(feeRecipient), 0);
        assertEq(bazaar.pendingEth(royaltyReceiver), 0);
        (address seller1_,,,,,) = bazaar.listing(address(royaltyNft), 1);
        (address seller2_,,,,,) = bazaar.listing(address(royaltyNft), 2);
        assertEq(seller1_, seller);
        assertEq(seller2_, seller);
        assertEq(address(attacker_).balance, 2 * PRICE);
    }

    function test_Attack_RevertWhen_ReceiverReentersWithdraw() public {
        ReentrantWithdrawer attacker_ = new ReentrantWithdrawer(bazaar);
        royaltyNft.setDefaultRoyalty(address(attacker_), 500);

        _listEth(1);
        vm.prank(buyer);
        bazaar.buyNFT{value: PRICE}(address(royaltyNft), 1, type(uint256).max);

        vm.expectRevert("Withdraw failed.");
        attacker_.attack();

        assertEq(bazaar.pendingEth(address(attacker_)), 0.05 ether);
        assertEq(address(attacker_).balance, 0);
        assertEq(address(bazaar).balance, PRICE);
        assertEq(bazaar.pendingEth(seller), 0.925 ether);
        assertEq(bazaar.pendingEth(feeRecipient), 0.025 ether);
    }

    // Blacklist

    function test_Attack_RevertWhen_RoyaltyReceiverIsBlacklisted() public {
        _listWithBlToken(1);
        _fundBuyerBl();
        blToken.setBlacklisted(royaltyReceiver, true);

        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(MockERC20Blacklist.Blacklisted.selector, royaltyReceiver));
        bazaar.buyNFT(address(royaltyNft), 1, type(uint256).max);

        assertEq(blToken.balanceOf(buyer), PRICE);
        assertEq(blToken.balanceOf(seller), 0);
        assertEq(blToken.balanceOf(feeRecipient), 0);
        assertEq(royaltyNft.ownerOf(1), seller);
        (address listedSeller_,,,,,) = bazaar.listing(address(royaltyNft), 1);
        assertEq(listedSeller_, seller);
    }

    function test_Attack_PurchaseSucceeds_AfterOwnerReplacesBlacklistedFeeRecipient() public {
        _listWithBlToken(1);
        _fundBuyerBl();
        blToken.setBlacklisted(feeRecipient, true);

        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(MockERC20Blacklist.Blacklisted.selector, feeRecipient));
        bazaar.buyNFT(address(royaltyNft), 1, type(uint256).max);

        address newFeeRecipient_ = makeAddr("newFeeRecipient");
        vm.prank(deployer);
        bazaar.setFeeRecipient(newFeeRecipient_);

        vm.prank(buyer);
        bazaar.buyNFT(address(royaltyNft), 1, type(uint256).max);

        assertEq(royaltyNft.ownerOf(1), buyer);
        assertEq(blToken.balanceOf(newFeeRecipient_), 0.025 ether);
        assertEq(blToken.balanceOf(seller), 0.925 ether);
        assertEq(blToken.balanceOf(royaltyReceiver), 0.05 ether);
    }

    // Relisting of a stale listing

    function test_Attack_NewOwnerOverwritesStaleListing() public {
        _listEth(1);
        address newOwner_ = makeAddr("newOwner");

        vm.prank(seller);
        royaltyNft.transferFrom(seller, newOwner_, 1);

        vm.startPrank(newOwner_);
        royaltyNft.approve(address(bazaar), 1);
        bazaar.listNFT(address(royaltyNft), 1, address(0), 2 * PRICE, 0);
        vm.stopPrank();

        (address listedSeller_,, uint256 listedPrice_,,,) = bazaar.listing(address(royaltyNft), 1);
        assertEq(listedSeller_, newOwner_);
        assertEq(listedPrice_, 2 * PRICE);

        // the original seller can no longer touch it
        vm.prank(seller);
        vm.expectRevert("Not listing's seller.");
        bazaar.cancelListing(address(royaltyNft), 1);

        // and the sale pays the new owner
        vm.prank(buyer);
        bazaar.buyNFT{value: 2 * PRICE}(address(royaltyNft), 1, 2 * PRICE);

        assertEq(bazaar.pendingEth(newOwner_), 1.85 ether);
        assertEq(bazaar.pendingEth(seller), 0);
    }

    function _listEth(uint256 id_) internal {
        vm.startPrank(seller);
        royaltyNft.approve(address(bazaar), id_);
        bazaar.listNFT(address(royaltyNft), id_, address(0), PRICE, 0);
        vm.stopPrank();
    }

    function _listWithBlToken(uint256 id_) internal {
        vm.startPrank(seller);
        royaltyNft.approve(address(bazaar), id_);
        bazaar.listNFT(address(royaltyNft), id_, address(blToken), PRICE, 0);
        vm.stopPrank();
    }

    function _fundBuyerBl() internal {
        blToken.mint(buyer, PRICE);
        vm.prank(buyer);
        blToken.approve(address(bazaar), PRICE);
    }
}
