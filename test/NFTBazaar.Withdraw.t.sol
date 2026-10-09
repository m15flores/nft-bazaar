// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

import "forge-std/Test.sol";
import "../src/NFTBazaar.sol";
import "./mocks/MockERC20.sol";
import "./mocks/MockERC721Royalty.sol";
import "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract NFTBazaarWithdrawTest is Test {
    NFTBazaar bazaar;
    address deployer;
    address seller;
    address buyer;
    address feeRecipient;
    address royaltyReceiver;

    uint16 feeBps;
    uint256 tokenId;
    
    MockERC20 token;
    MockERC721Royalty royaltyNft;

    uint256 constant PRICE = 1 ether;
    uint256 constant INITIAL_TIMESTAMP = 1_700_000_000;
    uint256 constant LISTING_DURATION = 7 days;
    uint16 constant INITIAL_FEE_BPS = 250;

    event Withdrawn(address indexed account, uint256 amount);

    function setUp() public {
       deployer = makeAddr("deployer");
        seller = makeAddr("seller");
        buyer = makeAddr("buyer");
        feeRecipient = makeAddr("feeRecipient");
        royaltyReceiver = makeAddr("royaltyReceiver");

        feeBps = INITIAL_FEE_BPS;
        tokenId = 1;

        token = new MockERC20();
        royaltyNft = new MockERC721Royalty();
        royaltyNft.mint(seller, tokenId);

        vm.warp(INITIAL_TIMESTAMP);
        vm.prank(deployer);
        bazaar = new NFTBazaar(feeRecipient, INITIAL_FEE_BPS);

        royaltyNft.setDefaultRoyalty(royaltyReceiver, 500);
        vm.deal(buyer, 100 ether);
    }

    // Positive cases
    
    function test_Withdraw_TransfersPendingEthCaller() public {
        _sellDefault();

        vm.prank(seller);
        bazaar.withdraw();

        assertEq(seller.balance, 0.925 ether);
        assertEq(bazaar.pendingEth(seller), 0);
        assertEq(address(bazaar).balance, 0.075 ether);
    }

    function test_Withdraw_DoesnotTouchOtherAccounts() public {
        _sellDefault();

        vm.prank(seller);
        bazaar.withdraw();

        assertEq(bazaar.pendingEth(feeRecipient), 0.025 ether);
        assertEq(bazaar.pendingEth(royaltyReceiver), 0.05 ether);
    }

    function test_Withdraw_LeavesContractEmptyWhenAllTreeWithdraw() public {
        _sellDefault();

        vm.prank(seller);
        bazaar.withdraw();

        vm.prank(feeRecipient);
        bazaar.withdraw();

        vm.prank(royaltyReceiver);
        bazaar.withdraw();

        assertEq(seller.balance, 0.925 ether);
        assertEq(feeRecipient.balance, 0.025 ether);
        assertEq(royaltyReceiver.balance, 0.05 ether);
        assertEq(address(bazaar).balance, 0);
    }

    // Fuzz

    function testFuzz_Withdraw_PaysExactyleWhatWasCredited(uint256 price_) public {
        price_ = bound(price_, 1, type(uint128).max);
        _list(price_, 0);

        vm.deal(buyer, price_);
        vm.prank(buyer);
        bazaar.buyNFT{value: price_}(address(royaltyNft), tokenId);

        uint256 sellerPending_ = bazaar.pendingEth(seller);
        uint256 feePending_ = bazaar.pendingEth(feeRecipient);
        uint256 royaltyPending_ = bazaar.pendingEth(royaltyReceiver);

        // fee 0 is possible with tiny prices, so only withdraw when there is balance
        vm.prank(seller);
        bazaar.withdraw();
        if(feePending_ > 0) {
            vm.prank(feeRecipient);
            bazaar.withdraw();
        }
        if(royaltyPending_ > 0) {
            vm.prank(royaltyReceiver);
            bazaar.withdraw();
        }

        assertEq(seller.balance, sellerPending_);
        assertEq(feeRecipient.balance, feePending_);
        assertEq(royaltyReceiver.balance, royaltyPending_);
        assertEq(address(bazaar).balance, 0);
    }

    // Events

    function test_Withdraw_EmitsWithdrawn() public {
        _sellDefault();

        vm.expectEmit(true, false, false, true);
        emit Withdrawn(seller, 0.925 ether);

        vm.prank(seller);
        bazaar.withdraw();
    }

    // Reverts

    function test_Withdraw_RevertWhen_NothingToWithdraw() public {
        vm.prank(seller);
        vm.expectRevert("Nothing to withdraw.");
        bazaar.withdraw();
    }

    function test_Withdraw_RevertWhen_WithdrawnTwice() public {
        _sellDefault();

        vm.startPrank(seller);
        bazaar.withdraw();

        vm.expectRevert("Nothing to withdraw.");
        bazaar.withdraw();

        assertEq(seller.balance, 0.925 ether);
        assertEq(address(bazaar).balance, 0.075 ether);

        vm.stopPrank();
    }

    function test_Withdraw_RevertWhen_ReceiverRejectsEth() public {
        address badReceiver_ = address(token);
        royaltyNft.setDefaultRoyalty(badReceiver_, 500);
        _sellDefault();

        vm.prank(badReceiver_);
        vm.expectRevert("Withdraw failed.");
        bazaar.withdraw();

        assertEq(bazaar.pendingEth(badReceiver_), 0.05 ether);
        assertEq(badReceiver_.balance, 0);
        assertEq(address(bazaar).balance, PRICE);
    }

    function _sellDefault() internal {
        _list(PRICE, 0);
        vm.prank(buyer);
        bazaar.buyNFT{value: PRICE}(address(royaltyNft), tokenId);
    }

    function _list(uint256 price_, uint256 endTime_) internal {
        vm.startPrank(seller);
        royaltyNft.approve(address(bazaar), tokenId);
        bazaar.listNFT(address(royaltyNft), tokenId, address(0), price_, endTime_);
        vm.stopPrank();
    }
}