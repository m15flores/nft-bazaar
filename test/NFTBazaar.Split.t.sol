// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

import "forge-std/Test.sol";
import "./harness/NFTBazaarHarness.sol";

contract NFTBazaarSplitTest is Test {

    NFTBazaarHarness harness;
    address deployer;
    address feeRecipient;
    uint16 feeBps;

    address nft;
    uint256 tokenId;

    function setUp() public {
        deployer = makeAddr("deployer");
        feeRecipient = makeAddr("feeRecipient");
        feeBps = 250;
        nft = makeAddr("nft");
        tokenId = 1;

        vm.prank(deployer);
        harness = new NFTBazaarHarness(feeRecipient, feeBps);
    }

    function test_ComputeSplit_NumericCase() public view {
        // 250 bps = 2.5%, and 2.5% of 1 ether = 0.025 ether
        uint256 price_ = 1 ether;
        uint256 expectedFee_ = 0.025 ether;
        uint256 expectedProceeds_ = price_ - expectedFee_;   // 0.975 ether

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
}