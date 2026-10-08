// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

import "forge-std/Test.sol";
import "./harness/NFTBazaarHarness.sol";
import "./mocks/MockERC721.sol";
import "./mocks/MockERC721Royalty.sol";
import "./mocks/MockERC721CustomRoyalty.sol";

contract NFTBazaarSplitTest is Test {

    NFTBazaarHarness harness;
    address deployer;
    address feeRecipient;
    uint16 feeBps;

    address nft;
    uint256 tokenId;

    MockERC721 plainNft;
    MockERC721Royalty royaltyNft;
    MockERC721CustomRoyalty customNft;
    address royaltyReceiver;

    function setUp() public {
        deployer = makeAddr("deployer");
        feeRecipient = makeAddr("feeRecipient");
        feeBps = 250;
        nft = makeAddr("nft");
        tokenId = 1;

        royaltyReceiver = makeAddr("royaltyReceiver");
        plainNft = new MockERC721();
        royaltyNft = new MockERC721Royalty();
        customNft = new MockERC721CustomRoyalty();

        vm.prank(deployer);
        harness = new NFTBazaarHarness(feeRecipient, feeBps);
    }

    function test_ComputeSplit_NumericCase() public view {
        // 250 bps = 2.5%, and 2.5% of 1 ether = 0.025 ether
        uint256 price_ = 1 ether;
        uint256 expectedFee_ = 0.025 ether;
        uint256 expectedProceeds_ = price_ - expectedFee_; // 0.975 ether

        (uint256 fee_, , , uint256 proceeds_) = harness.computeSplit(nft, tokenId, price_);

        assertEq(fee_, expectedFee_);
        assertEq(proceeds_, expectedProceeds_);
    }

    function test_ComputeSplit_FeeIsZero() public {       
        uint256 price_ = 1 ether;
        vm.prank(deployer);
        harness.setFee(0);
        (uint256 fee_, , , uint256 proceeds_) = harness.computeSplit(nft, tokenId, price_);

        assertEq(fee_, 0);
        assertEq(proceeds_, price_);
    }

    function test_ComputeSplit_FeeIsMaxFeeBps() public {
        uint256 price_ = 1 ether;
        uint16 maxFeeBps_ = harness.MAX_FEE_BPS();
        vm.prank(deployer);
        harness.setFee(maxFeeBps_);
        (uint256 fee_, , , ) = harness.computeSplit(nft, tokenId, price_);

        assertEq(fee_, 0.1 ether);
    }

    function test_ComputeSplit_FeeRoundsDownToZero_WhenPriceIs39() public view {
        uint256 price_ = 39;
        (uint256 fee_, , , uint256 proceeds_) = harness.computeSplit(nft, tokenId, price_);

        assertEq(fee_, 0);
        assertEq(proceeds_, price_);
    }

    function test_ComputeSplit_FeeIsOneWei_WhenPriceIs40() public view {
        // 40 * 250 = 10_000, and 10_000 / 10_000 = 1 (exact)
        uint256 price_ = 40;
        uint256 expectedFee_ = 1;
        uint256 expectedProceeds_ = price_ - expectedFee_;
        (uint256 fee_, , , uint256 proceeds_) = harness.computeSplit(nft, tokenId, price_);

        assertEq(fee_, expectedFee_);
        assertEq(proceeds_, expectedProceeds_);
    }

    function testFuzz_ComputeSplit_FeeIsFloorAndPartsAddUp(uint256 price_, uint16 feeBps_) public {
        price_ = bound(price_, 0, type(uint128).max);
        feeBps_ = uint16(bound(feeBps_, 0, harness.MAX_FEE_BPS()));
        vm.prank(deployer);
        harness.setFee(feeBps_);
        (uint256 fee_, , , uint256 proceeds_) = harness.computeSplit(nft, tokenId, price_);

        // fee is exactly floor(price * bps / 10_000)
        assertEq(fee_ + proceeds_, price_);
        assertLe(fee_, price_);
        assertLe(fee_ * 10_000, price_ * feeBps_);
        assertLt(price_ * feeBps_, (fee_ + 1) * 10_000);
    }

    function test_ComputeSplit_RevertWhen_PriceTimesFeeOverflows() public {
        // feeBps must be > 0: with 0, max * 0 does not overflow
        vm.expectRevert(stdError.arithmeticError);
        harness.computeSplit(nft, tokenId, type(uint256).max);
    }

    // With Royalties

    function test_ComputeSplit_NumericCase_WithRoyalty() public {
        uint256 price_ = 1 ether;
        // fee : 250 bps = 2.5% of 1 ether
        uint256 expectedFee_ = 0.025 ether;
        // royalty : 500 bps = 5% of 1 ether
        uint256 expectedRoyalty_ = 0.05 ether;
        uint256 expectedProceeds_ = price_ - expectedFee_ - expectedRoyalty_;

        royaltyNft.setDefaultRoyalty(royaltyReceiver, 500);

        (uint256 fee_, address royaltyReceiver_, uint256 royalty_, uint256 proceeds_) = harness.computeSplit(address(royaltyNft), tokenId, price_);

        assertEq(fee_, expectedFee_);
        assertEq(royalty_, expectedRoyalty_);
        assertEq(royaltyReceiver_, royaltyReceiver);
        assertEq(proceeds_, expectedProceeds_);
    }

    function test_ComputeSplit_NoRoyalty_WhenNFTDoesNotSupportERC2981() public view {
        uint256 price_ = 1 ether;
        uint256 expectedFee_ = 0.025 ether;
        uint256 expectedRoyalty_ = 0;
        uint256 expectedProceeds_ = price_ - expectedFee_ - expectedRoyalty_;

        (uint256 fee_, address royaltyReceiver_, uint256 royalty_, uint256 proceeds_) = harness.computeSplit(address(plainNft), tokenId, price_);

        assertEq(fee_, expectedFee_);
        assertEq(royalty_, expectedRoyalty_);
        assertEq(royaltyReceiver_, address(0));
        assertEq(proceeds_, expectedProceeds_);
    }

    function test_ComputeSplit_Succeeds_WhenFeePlusRoyaltyEqualsPrice() public {
        uint256 price_ = 1 ether;
        uint256 expectedFee_ = 0.025 ether;
        uint256 royalty = price_ - expectedFee_; // the royalty takes everything left
        uint256 expectedProceeds_ = 0;

        customNft.setRoyalty(royaltyReceiver, royalty);

        (uint256 fee_, address royaltyReceiver_, uint256 royalty_, uint256 proceeds_) = harness.computeSplit(address(customNft), tokenId, price_);

        assertEq(fee_, expectedFee_);
        assertEq(royalty_, royalty);
        assertEq(royaltyReceiver_, royaltyReceiver);
        assertEq(proceeds_, expectedProceeds_);
    }

    function test_ComputeSplit_RoyaltyIsZero_WhenReceiverIsZeroAddress() public {
        uint256 price_ = 1 ether;
        uint256 royalty = 0.05 ether; // not zero and below the limit
        customNft.setRoyalty(address(0), royalty);

        (uint256 fee_, address royaltyReceiver_, uint256 royalty_, uint256 proceeds_) = harness.computeSplit(address(customNft), tokenId, price_);

        assertEq(royalty_, 0);
        assertEq(royaltyReceiver_, address(0));
        assertEq(proceeds_, price_ - fee_);
    }

    function testFuzz_ComputeSplit_PartsAddUp_WithRoyalty(uint256 price_, uint16 feeBps_, uint96 royaltyBps_) public {
        
        uint16 maxFeeBps_ = harness.MAX_FEE_BPS();
        price_ = bound(price_, 0, type(uint128).max);
        feeBps_ = uint16(bound(feeBps_, 0, maxFeeBps_));
        royaltyBps_ = uint96(bound(royaltyBps_, 0, 10_000 - feeBps_));

        vm.prank(deployer);
        harness.setFee(feeBps_);
        royaltyNft.setDefaultRoyalty(royaltyReceiver, royaltyBps_);

        (uint256 fee, address receiver, uint256 royalty, uint256 proceeds) = harness.computeSplit(address(royaltyNft), tokenId, price_);

        assertEq(fee + royalty + proceeds, price_);
        assertEq(receiver, royaltyReceiver);
        assertEq(royalty, (price_ * royaltyBps_) / 10_000);
    }

    function test_ComputeSplit_RevertWhen_FeePlusRoyaltyExceedsPrice() public {
        uint256 price_ = 1 ether;
        uint256 expectedFee_ = 0.025 ether;
        uint256 royalty = price_ - expectedFee_ + 1; // the royalty is bigger

        customNft.setRoyalty(royaltyReceiver, royalty);

        vm.expectRevert("Fee plus royalty exceed price.");
        harness.computeSplit(address(customNft), tokenId, price_);        
    }

    function test_ComputeSplit_RevertWhen_RoyaltyIsMaxUint() public {
        uint256 price_ = 1 ether;
        uint256 royalty = type(uint256).max;

        customNft.setRoyalty(royaltyReceiver, royalty);

        vm.expectRevert("Fee plus royalty exceed price.");
        harness.computeSplit(address(customNft), tokenId, price_); 
    }
}