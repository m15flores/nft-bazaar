// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

import "forge-std/Test.sol";
import "../src/NFTBazaar.sol";
import "./mocks/MockERC20.sol";
import "./mocks/MockERC721Royalty.sol";
import "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract NFTBazaarBuyTest is Test {

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

    event NFTSold(address indexed buyer, address indexed seller, address indexed nft, uint256 tokenId, address paymentToken, uint256 price);

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

    function test_BuyNFT_TransfersNFTAndCreditsPendingEth() public {
        _listDefault(block.timestamp + LISTING_DURATION);

        vm.prank(buyer);
        bazaar.buyNFT{value: PRICE}(address(royaltyNft), tokenId);

        // fee 2.5% = 0.025, royalty 5% = 0.05, proceeds = 0.925
        assertEq(royaltyNft.ownerOf(tokenId), buyer);
        assertEq(bazaar.pendingEth(seller), 0.925 ether);
        assertEq(bazaar.pendingEth(feeRecipient), 0.025 ether);
        assertEq(bazaar.pendingEth(royaltyReceiver), 0.05 ether);
        assertEq(address(bazaar).balance, PRICE);
    }

    function test_BuyNFT_DeletesListing() public {
        _listDefault(block.timestamp + LISTING_DURATION);

        vm.prank(buyer);
        bazaar.buyNFT{value: PRICE}(address(royaltyNft), tokenId);

        (address listedSeller_,,,,,) = bazaar.listing(address(royaltyNft), tokenId);
        assertEq(listedSeller_, address(0));
    }

    function test_BuyNFT_SucceedsWhenEndTimeIsZero() public {
        _listDefault(0);
        vm.warp(block.timestamp + 365 days);

        vm.prank(buyer);
        bazaar.buyNFT{value: PRICE}(address(royaltyNft), tokenId);

        assertEq(royaltyNft.ownerOf(tokenId), buyer);
    }

    function test_BuyNFT_SucceedsOneSecondBeforeExpiry() public {
        uint256 endTime_ = block.timestamp + LISTING_DURATION;
        _listDefault(endTime_);
        vm.warp(endTime_ - 1);

        vm.prank(buyer);
        bazaar.buyNFT{value: PRICE}(address(royaltyNft), tokenId);

        assertEq(royaltyNft.ownerOf(tokenId), buyer);
    }

    function test_BuyNFT_PaysUpdatedPrice() public {
        _listDefault(0);

        vm.prank(seller);
        bazaar.updatePrice(address(royaltyNft), tokenId, PRICE * 2);

        vm.prank(buyer);
        bazaar.buyNFT{value: PRICE * 2}(address(royaltyNft), tokenId);

        // fee 0.05, royalty 0.1, proceeds 1.85
        assertEq(bazaar.pendingEth(seller), 1.85 ether);
        assertEq(bazaar.pendingEth(feeRecipient), 0.05 ether);
        assertEq(bazaar.pendingEth(royaltyReceiver), 0.1 ether);
        assertEq(address(bazaar).balance, PRICE * 2);
    }

    // Fuzz

    function testFuzz_BuyNFT_CreditsExactlyThePrice(uint256 price_, uint16 feeBps_, uint96 royaltyBps_) public {
        uint16 maxFeeBps_ = bazaar.MAX_FEE_BPS();
        price_ = bound(price_, 1, type(uint128).max);
        feeBps_ = uint16(bound(feeBps_, 0, maxFeeBps_));
        royaltyBps_ = uint96(bound(royaltyBps_, 0, bazaar.BPS_DENOMINATOR() - feeBps_));

        vm.prank(deployer);
        bazaar.setFee(feeBps_);

        royaltyNft.setDefaultRoyalty(royaltyReceiver, royaltyBps_);

        _list(price_, 0);

        uint256 expectedFee_ = (price_ * feeBps_) / bazaar.BPS_DENOMINATOR();
        (, uint256 expectedRoyalty_) = royaltyNft.royaltyInfo(tokenId, price_);

        vm.deal(buyer, price_);
        vm.prank(buyer);
        bazaar.buyNFT{value: price_}(address(royaltyNft), tokenId);

        assertEq(bazaar.pendingEth(feeRecipient), expectedFee_);
        assertEq(bazaar.pendingEth(royaltyReceiver), expectedRoyalty_);
        assertEq(bazaar.pendingEth(seller), price_ - expectedFee_ - expectedRoyalty_);
        assertEq(price_, bazaar.pendingEth(seller) + bazaar.pendingEth(feeRecipient) + bazaar.pendingEth(royaltyReceiver));
        assertEq(address(bazaar).balance, price_);
        assertEq(royaltyNft.ownerOf(tokenId), buyer);
    }

    // Events

    function test_BuyNFT_EmitsNFTSold() public {
        _listDefault(0);

        vm.expectEmit(true, true, true, true);
        emit NFTSold(buyer, seller, address(royaltyNft), tokenId, address(0), PRICE);

        vm.prank(buyer);
        bazaar.buyNFT{value: PRICE}(address(royaltyNft), tokenId);
    }

    // Reverts

    function test_BuyNFT_RevertWhen_ListingExpired() public {
        uint256 endTime_ = block.timestamp + LISTING_DURATION;
        _listDefault(endTime_);
        vm.warp(endTime_); // exactly at the limit: already expired

        vm.prank(buyer);
        vm.expectRevert("Listing expired.");
        bazaar.buyNFT{value: PRICE}(address(royaltyNft), tokenId);

        (address listedSeller_,,,,,) = bazaar.listing(address(royaltyNft), tokenId);
        assertEq(listedSeller_, seller);
        assertEq(royaltyNft.ownerOf(tokenId), seller);
        assertEq(address(bazaar).balance, 0);
    }

    function test_BuyNFT_RevertWhen_ListingDoesNotExist() public {
        vm.prank(buyer);
        vm.expectRevert("Listing does not exist.");
        bazaar.buyNFT{value: PRICE}(address(royaltyNft), tokenId);
        
        (address listedSeller_,,,,,) = bazaar.listing(address(royaltyNft), tokenId);
        assertEq(listedSeller_, address(0));
        assertEq(royaltyNft.ownerOf(tokenId), seller);
        assertEq(address(bazaar).balance, 0);
    }

    function test_BuyNFT_RevertWhen_PaymentIsLessThanPrice() public {
        uint256 endTime_ = block.timestamp + LISTING_DURATION;
        _listDefault(endTime_);
        vm.warp(endTime_ - 1);

        vm.prank(buyer);
        vm.expectRevert("Incorrect payment.");
        bazaar.buyNFT{value: PRICE - 1}(address(royaltyNft), tokenId);

        (address listedSeller_,,,,,) = bazaar.listing(address(royaltyNft), tokenId);
        assertEq(listedSeller_, seller);
        assertEq(royaltyNft.ownerOf(tokenId), seller);
        assertEq(address(bazaar).balance, 0);
    }

    function test_BuyNFT_RevertWhen_PaymentIsMoreThanPrice() public {
        uint256 endTime_ = block.timestamp + LISTING_DURATION;
        _listDefault(endTime_);
        vm.warp(endTime_ - 1);

        vm.prank(buyer);
        vm.expectRevert("Incorrect payment.");
        bazaar.buyNFT{value: PRICE + 1}(address(royaltyNft), tokenId);

        (address listedSeller_,,,,,) = bazaar.listing(address(royaltyNft), tokenId);
        assertEq(listedSeller_, seller);
        assertEq(royaltyNft.ownerOf(tokenId), seller);
        assertEq(address(bazaar).balance, 0);
    }

    function test_BuyNFT_RevertWhen_PaymentTokenIsERC20() public {
        uint256 endTime_ = block.timestamp + LISTING_DURATION;

        vm.prank(deployer);
        bazaar.setAllowedToken(address(token), true);

        vm.startPrank(seller);
        royaltyNft.approve(address(bazaar), tokenId);
        bazaar.listNFT(address(royaltyNft), tokenId, address(token), PRICE, endTime_);
        vm.stopPrank();

        vm.warp(endTime_ - 1);

        vm.prank(buyer);
        vm.expectRevert("ERC20 payments not supported yet.");
        bazaar.buyNFT{value: PRICE}(address(royaltyNft), tokenId);

        (address listedSeller_,,,,,) = bazaar.listing(address(royaltyNft), tokenId);
        assertEq(listedSeller_, seller);
        assertEq(royaltyNft.ownerOf(tokenId), seller);
        assertEq(address(bazaar).balance, 0);
    }

    function test_BuyNFT_RevertWhen_ListingIsStale() public {
        _listDefault(0);
        address newOwner_ = makeAddr("newOwner");

        vm.prank(seller);
        royaltyNft.transferFrom(seller, newOwner_, tokenId);

        vm.prank(buyer);
        vm.expectRevert(
            abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, address(bazaar), tokenId)
        );
        bazaar.buyNFT{value: PRICE}(address(royaltyNft), tokenId);

        (address listedSeller_,,,,,) = bazaar.listing(address(royaltyNft), tokenId);
        assertEq(listedSeller_, seller);
        assertEq(bazaar.pendingEth(seller), 0);
        assertEq(royaltyNft.ownerOf(tokenId), newOwner_);
        assertEq(address(bazaar).balance, 0);
    }

    function test_BuyNFT_RevertWhen_BuyerCannotReceiveNFT() public {
        address badBuyer_ = address(token);
        vm.deal(badBuyer_, PRICE);
        _listDefault(0);

        vm.prank(badBuyer_);
        vm.expectRevert(
            abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, badBuyer_)
        );
        bazaar.buyNFT{value: PRICE}(address(royaltyNft), tokenId);

        (address listedSeller_,,,,,) = bazaar.listing(address(royaltyNft), tokenId);
        assertEq(listedSeller_, seller);
        assertEq(royaltyNft.ownerOf(tokenId), seller);
        assertEq(address(bazaar).balance, 0);
        assertEq(bazaar.pendingEth(seller), 0);
        assertEq(bazaar.pendingEth(feeRecipient), 0);
        assertEq(bazaar.pendingEth(royaltyReceiver), 0);
    }

    function test_BuyNFT_RevertWhen_BoughtTwice() public {
        // First purchase
        _listDefault(block.timestamp + LISTING_DURATION);
        vm.prank(buyer);
        bazaar.buyNFT{value: PRICE}(address(royaltyNft), tokenId);

        // Second purchase
        address secondBuyer_ = makeAddr("secondBuyer");
        vm.deal(secondBuyer_, PRICE);

        vm.prank(secondBuyer_);
        vm.expectRevert("Listing does not exist.");
        bazaar.buyNFT{value: PRICE}(address(royaltyNft), tokenId);

        assertEq(royaltyNft.ownerOf(tokenId), buyer);
        assertEq(address(bazaar).balance, PRICE); // Only the first purchase
        assertEq(secondBuyer_.balance, PRICE); // the revert returned the sencond buyer's ETH
    }


    function _listDefault(uint256 endTime_) internal {
        vm.startPrank(seller);
        royaltyNft.approve(address(bazaar), tokenId);
        bazaar.listNFT(address(royaltyNft), tokenId, address(0), PRICE, endTime_);
        vm.stopPrank();
    }

    function _list(uint256 price_, uint256 endTime_) internal {
        vm.startPrank(seller);
        royaltyNft.approve(address(bazaar), tokenId);
        bazaar.listNFT(address(royaltyNft), tokenId, address(0), price_, endTime_);
        vm.stopPrank();
    }
}