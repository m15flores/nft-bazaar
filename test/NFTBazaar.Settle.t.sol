// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

import "forge-std/Test.sol";
import "./harness/NFTBazaarHarness.sol";
import "./mocks/MockERC20.sol";
import "./mocks/MockERC721.sol";
import "./mocks/MockERC721Royalty.sol";
import "./mocks/MockERC721CustomRoyalty.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract NFTBazaarSettleTest is Test {

    NFTBazaarHarness harness;
    address deployer;
    address seller;
    address buyer;
    address feeRecipient;
    address royaltyReceiver;

    uint16 feeBps;
    uint256 tokenId;
    
    MockERC20 token;
    MockERC721 plainNft;
    MockERC721Royalty royaltyNft;
    MockERC721CustomRoyalty customNft;

    event NFTSold(address indexed buyer, address indexed seller, address indexed nft, uint256 tokenId, address paymentToken, uint256 price);

    function setUp() public {
        deployer = makeAddr("deployer");
        seller = makeAddr("seller");
        buyer = makeAddr("buyer");
        feeRecipient = makeAddr("feeRecipient");
        royaltyReceiver = makeAddr("royaltyReceiver");

        feeBps = 250;
        tokenId = 1;

        token = new MockERC20();
        plainNft = new MockERC721();
        royaltyNft = new MockERC721Royalty();
        customNft = new MockERC721CustomRoyalty();
        plainNft.mint(seller, tokenId);
        royaltyNft.mint(seller, tokenId);
        customNft.mint(seller, tokenId);

        vm.prank(deployer);
        harness = new NFTBazaarHarness(feeRecipient, feeBps);
    }

    /* _settle */

    // Positive cases

    function test_Settle_CreditsSellerFeeRecipientAndRoyaltyReceiver() public {
        uint256 price_ = 1 ether;
        uint96 royaltyBps_ = 500;
        // fee: 250 bps = 2.5%, royalty: 500 bps = 5%
        uint256 expectedFee_ = 0.025 ether;
        uint256 expectedRoyalty_ = 0.05 ether;
        uint256 expectedProceeds_ = price_ - expectedFee_ - expectedRoyalty_;

        royaltyNft.setDefaultRoyalty(royaltyReceiver, royaltyBps_);
        _approveHarness(address(royaltyNft));

        harness.settle{value: price_}(address(royaltyNft), tokenId, seller, buyer, address(0), price_);

        assertEq(harness.pendingEth(seller), expectedProceeds_);
        assertEq(harness.pendingEth(feeRecipient), expectedFee_);
        assertEq(harness.pendingEth(royaltyReceiver), expectedRoyalty_);
        assertEq(address(harness).balance, price_);
    }

    function test_Settle_NoRoyalty_WhenNFTDoesNotSupportERC2981() public {
        uint256 price_ = 1 ether;

        uint256 expectedFee_ = 0.025 ether;
        uint256 expectedRoyalty_ = 0;
        uint256 expectedProceeds_ = price_ - expectedFee_ - expectedRoyalty_;

        _approveHarness(address(plainNft));

        harness.settle{value: price_}(address(plainNft), tokenId, seller, buyer, address(0), price_);

        assertEq(harness.pendingEth(seller), expectedProceeds_);
        assertEq(harness.pendingEth(feeRecipient), expectedFee_);
        assertEq(harness.pendingEth(royaltyReceiver), expectedRoyalty_);
    }

    function test_Settle_RoyaltyReceiverIsAddressZero() public {
        uint256 price_ = 1 ether;
        uint256 royalty = 0.05 ether; // not zero and below price - fee
        
        uint256 expectedFee_ = 0.025 ether;
        uint256 expectedRoyalty_ = 0;
        uint256 expectedProceeds_ = price_ - expectedFee_ - expectedRoyalty_;

        customNft.setRoyalty(address(0), royalty);
        _approveHarness(address(customNft));

        harness.settle{value: price_}(address(customNft), tokenId, seller, buyer, address(0), price_);

        assertEq(harness.pendingEth(seller), expectedProceeds_);
        assertEq(harness.pendingEth(feeRecipient), expectedFee_);
        assertEq(harness.pendingEth(address(0)), expectedRoyalty_);
        assertEq(address(harness).balance, price_);
    }

    function test_Settle_TransfersNFTFromSellerToBuyer() public {
        _approveHarness(address(royaltyNft));

        harness.settle{value: 1 ether}(address(royaltyNft), tokenId, seller, buyer, address(0), 1 ether);

        assertEq(royaltyNft.ownerOf(tokenId), buyer);
    }

    function test_Settle_WhenFeeRecipientIsSeller() public {
        vm.prank(deployer);
        harness.setFeeRecipient(seller);

        uint256 price_ = 1 ether;
        uint96 royaltyBps_ = 500;
        
        uint256 expectedFee_ = 0.025 ether;
        uint256 expectedRoyalty_ = 0.05 ether;
        uint256 expectedProceeds_ = price_ - expectedFee_ - expectedRoyalty_;

        royaltyNft.setDefaultRoyalty(royaltyReceiver, royaltyBps_);
        _approveHarness(address(royaltyNft));

        harness.settle{value: price_}(address(royaltyNft), tokenId, seller, buyer, address(0), price_);

        assertEq(harness.pendingEth(seller), expectedFee_ + expectedProceeds_);
        assertEq(harness.pendingEth(royaltyReceiver), expectedRoyalty_);
        assertEq(address(harness).balance, price_);
    }

    function test_Settle_WhenRoyaltyReceiverIsSeller() public {
        royaltyReceiver = seller;

        uint256 price_ = 1 ether;
        uint96 royaltyBps_ = 500;
        
        uint256 expectedFee_ = 0.025 ether;
        uint256 expectedRoyalty_ = 0.05 ether;
        uint256 expectedProceeds_ = price_ - expectedFee_ - expectedRoyalty_;

        royaltyNft.setDefaultRoyalty(royaltyReceiver, royaltyBps_);
        _approveHarness(address(royaltyNft));

        harness.settle{value: price_}(address(royaltyNft), tokenId, seller, buyer, address(0), price_);

        assertEq(harness.pendingEth(seller), expectedProceeds_ + expectedRoyalty_);
        assertEq(harness.pendingEth(feeRecipient), expectedFee_);
        assertEq(address(harness).balance, price_);
    }

    function test_Settle_WhenFeeRecipientIsRoyaltyReceiver() public {
        royaltyReceiver = feeRecipient;

        uint256 price_ = 1 ether;
        uint96 royaltyBps_ = 500;
        
        uint256 expectedFee_ = 0.025 ether;
        uint256 expectedRoyalty_ = 0.05 ether;
        uint256 expectedProceeds_ = price_ - expectedFee_ - expectedRoyalty_;

        royaltyNft.setDefaultRoyalty(royaltyReceiver, royaltyBps_);
        _approveHarness(address(royaltyNft));

        harness.settle{value: price_}(address(royaltyNft), tokenId, seller, buyer, address(0), price_);

        assertEq(harness.pendingEth(seller), expectedProceeds_);
        assertEq(harness.pendingEth(feeRecipient), expectedFee_ + expectedRoyalty_);
        assertEq(address(harness).balance, price_);
    }

    function test_Settle_Accumulates_WhenFeeRecipientAndRoyaltyReceiverAreSeller() public {
        vm.prank(deployer);
        harness.setFeeRecipient(seller);
        royaltyReceiver = seller;

        uint256 price_ = 1 ether;
        uint96 royaltyBps_ = 500;
        
        uint256 expectedFee_ = 0.025 ether;
        uint256 expectedRoyalty_ = 0.05 ether;
        uint256 expectedProceeds_ = price_ - expectedFee_ - expectedRoyalty_;

        royaltyNft.setDefaultRoyalty(royaltyReceiver, royaltyBps_);
        _approveHarness(address(royaltyNft));

        harness.settle{value: price_}(address(royaltyNft), tokenId, seller, buyer, address(0), price_);

        assertEq(harness.pendingEth(seller), expectedFee_ + expectedProceeds_ + expectedRoyalty_);
        assertEq(address(harness).balance, price_);
    }

    function test_Settle_AccumulatesAcrossTwoSales() public {
        uint256 secondTokenId_ = 2;
        royaltyNft.mint(seller, secondTokenId_);
        royaltyNft.setDefaultRoyalty(royaltyReceiver, 500);
        _approveHarness(address(royaltyNft));
        _approveHarness(address(royaltyNft), secondTokenId_);

        // 1. First sell: 1 ether, so fee 0.025, royalty 0.05, proceeds 0.925
        harness.settle{value: 1 ether}(address(royaltyNft), tokenId, seller, buyer, address(0), 1 ether);
        assertEq(harness.pendingEth(seller), 0.925 ether);

        // 2. Second sell: 2 ether, so fee 0.05, royalty 0.1, proceeds 1.85
        harness.settle{value: 2 ether}(address(royaltyNft), secondTokenId_, seller, buyer, address(0), 2 ether);

        assertEq(harness.pendingEth(seller), 0.925 ether + 1.85 ether);
        assertEq(harness.pendingEth(feeRecipient), 0.025 ether + 0.05 ether);
        assertEq(harness.pendingEth(royaltyReceiver), 0.05 ether + 0.1 ether);
        assertEq(address(harness).balance, 3 ether);
    }

    function test_Settle_CreditsZeroProceeds_WhenRoyaltyEqualsPriceMinusFee() public {
        uint256 price_ = 1 ether;
        uint256 expectedFee_ = 0.025 ether;
        uint256 royalty_ = price_ - expectedFee_;

        customNft.setRoyalty(royaltyReceiver, royalty_);
        _approveHarness(address(customNft));

        harness.settle{value: price_}(address(customNft), tokenId, seller, buyer, address(0), price_);

        assertEq(harness.pendingEth(seller), 0);
        assertEq(harness.pendingEth(royaltyReceiver), royalty_);
        assertEq(_totalPending(), price_);
    }

    // Fuzz

    function testFuzz_Settle_CreditsExactlyThePrice(uint256 price_, uint16 feeBps_, uint96 royaltyBps_) public {
        uint256 maxFeeBps_ = harness.MAX_FEE_BPS();
        price_ = bound(price_, 0, type(uint128).max);
        feeBps_ = uint16(bound(feeBps_, 0, maxFeeBps_));
        royaltyBps_ = uint96(bound(royaltyBps_, 0, harness.BPS_DENOMINATOR() - feeBps_));

        vm.prank(deployer);
        harness.setFee(feeBps_);
        royaltyNft.setDefaultRoyalty(royaltyReceiver, royaltyBps_);
        _approveHarness(address(royaltyNft));

        (uint256 fee, address receiver, uint256 royalty, uint256 proceeds) =
            harness.computeSplit(address(royaltyNft), tokenId, price_);

        vm.deal(address(this), price_);
        harness.settle{value: price_}(address(royaltyNft), tokenId, seller, buyer, address(0), price_);

        assertEq(harness.pendingEth(seller), proceeds);
        assertEq(harness.pendingEth(feeRecipient), fee);
        assertEq(harness.pendingEth(receiver), royalty);
        assertEq(_totalPending(), price_);
        assertEq(address(harness).balance, price_);
        assertEq(royaltyNft.ownerOf(tokenId), buyer);
    }

    // Events
    
    function test_Settle_EmitsNFTSold() public {
        uint256 price_ = 1 ether;
        uint96 royaltyBps_ = 500;

        royaltyNft.setDefaultRoyalty(royaltyReceiver, royaltyBps_);
        _approveHarness(address(royaltyNft));

        vm.expectEmit(true, true, true, true);
        emit NFTSold(buyer, seller, address(royaltyNft), tokenId, address(0), price_);

        harness.settle{value: price_}(address(royaltyNft), tokenId, seller, buyer, address(0), price_);
    }

    // Reverts

    function test_Settle_RevertWhen_SelletNotOwner() public {
        address notOwner_ = makeAddr("notOwner");
        uint256 price_ = 1 ether;

        royaltyNft.setDefaultRoyalty(royaltyReceiver, 500);
        _approveHarness(address(royaltyNft));

        vm.expectRevert(
            abi.encodeWithSelector(IERC721Errors.ERC721IncorrectOwner.selector, notOwner_, tokenId, seller)
        );
        harness.settle{value: price_}(address(royaltyNft), tokenId, notOwner_, buyer, address(0), price_);

        assertEq(_totalPending(), 0);
        assertEq(address(harness).balance, 0);
    }

    function test_Settle_RevertWhen_BazaarNotApproved() public {
        uint256 price_ = 1 ether;
        uint96 royaltyBps_ = 500;

        royaltyNft.setDefaultRoyalty(royaltyReceiver, royaltyBps_);

        vm.expectRevert(
            abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, address(harness), tokenId)
        );
        harness.settle{value: price_}(address(royaltyNft), tokenId, seller, buyer, address(0), price_);

        assertEq(_totalPending(), 0);
        assertEq(address(harness).balance, 0);
    }

    function test_Settle_RevertWhen_BuyerCannotReceiveNFT() public {
        address receiver_ = address(token);
        uint256 price_ = 1 ether;

        royaltyNft.setDefaultRoyalty(royaltyReceiver, 500);
        _approveHarness(address(royaltyNft));

        vm.expectRevert(
            abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, receiver_)
        );
        harness.settle{value: price_}(address(royaltyNft), tokenId, seller, receiver_, address(0), price_);

        assertEq(_totalPending(), 0);
        assertEq(address(harness).balance, 0);
        assertEq(royaltyNft.ownerOf(tokenId), seller);
    }
    
    function test_Settle_RevertWhen_FeePlusRoyaltyExceedsPrice() public {
        uint256 price_ = 1 ether;
        uint256 expectedFee_ = 0.025 ether;
        uint256 royalty = price_ - expectedFee_ + 1;
        
        customNft.setRoyalty(royaltyReceiver, royalty);
        _approveHarness(address(customNft));

        vm.expectRevert("Fee plus royalty exceed price.");
        harness.settle{value: price_}(address(customNft), tokenId, seller, buyer, address(0), price_);
        
        assertEq(_totalPending(), 0);
        assertEq(address(harness).balance, 0);
    }

    function _approveHarness(address nft_) internal {
        vm.prank(seller);
        IERC721(nft_).approve(address(harness), tokenId);
    }

    function _approveHarness(address nft_, uint256 tokenId_) internal {
        vm.prank(seller);
        IERC721(nft_).approve(address(harness), tokenId_);
    }

    function _totalPending() internal view returns (uint256) {
        return harness.pendingEth(seller)
            + harness.pendingEth(feeRecipient)
            + harness.pendingEth(royaltyReceiver);
    }
}