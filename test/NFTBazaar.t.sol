// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

import "forge-std/Test.sol";
import "../src/NFTBazaar.sol";
import "./mocks/MockERC20.sol";
import "./mocks/MockERC721.sol";

contract NFTBazaarTest is Test {
    
    NFTBazaar bazaar;
    address deployer;
    address feeRecipient;
    uint16 feeBps;
    address randomUser;
    address seller;
    uint256 tokenId;

    MockERC20 token;
    MockERC721 nft;

    uint256 constant LISTING_DURATION = 7 days;
    uint256 constant INITIAL_TIMESTAMP = 1_700_000_000;
    uint256 constant DEFAULT_PRICE = 10;

    event FeeSet(uint16 feeBps_);
    event FeeRecipientSet(address indexed feeRecipient_);
    event AllowedTokenSet(address indexed token_, bool allowed_);
    event NFTListed(address indexed seller, address indexed nft, uint256 indexed tokenId, address paymentToken, uint256 price, uint256 endTime);
    event NFTCancelled(address indexed seller, address indexed nft, uint256 indexed tokenId);
    event NFTSold(address indexed buyer, address indexed seller, address indexed nftAddress, uint256 tokenId, uint256 price);

    function setUp() public {
        deployer = makeAddr("deployer");
        feeRecipient = makeAddr("feeRecipient");
        feeBps = 250;
        randomUser = makeAddr("randomUser");
        token = new MockERC20();
        nft = new MockERC721();
        seller = makeAddr("seller");
        tokenId = 1;
        
        vm.warp(INITIAL_TIMESTAMP);
        vm.startPrank(deployer);
        bazaar = new NFTBazaar(feeRecipient, feeBps);
        nft.mint(seller, tokenId);
        vm.stopPrank();
    }

    /* constructor */

    // Positive cases

    function test_Constructor_SetsInitialState() public view {
        assertEq(bazaar.owner(), deployer);
        assertEq(bazaar.feeRecipient(), feeRecipient);
        assertEq(bazaar.feeBps(), feeBps);
    }

    function test_Constructor_AcceptsMaxFee() public {
        uint16 maxFee_ = bazaar.MAX_FEE_BPS();   // leer la constante antes del prank

        vm.prank(deployer);
        NFTBazaar bazaarMax_ = new NFTBazaar(feeRecipient, maxFee_);

        assertEq(bazaarMax_.feeBps(), maxFee_);
    }

    // Events

    function test_Constructor_EmitsFeeSet() public {
        vm.expectEmit(false, false, false, true);
        emit FeeSet(feeBps);

        vm.prank(deployer);
        new NFTBazaar(feeRecipient, feeBps);
    }

    function test_Constructor_EmitsFeeRecipientSet() public {
        vm.expectEmit(true, false, false, true);
        emit FeeRecipientSet(feeRecipient);

        vm.prank(deployer);
        new NFTBazaar(feeRecipient, feeBps);
    }
    
    // Reverts

    function test_Constructor_RevertWhen_FeeAboveMax() public {
        uint16 feeBpsGreaterThanMax_ = bazaar.MAX_FEE_BPS() + 1;
        vm.expectRevert("Fee Base Points cannot be greater than 10%.");
        new NFTBazaar(feeRecipient, feeBpsGreaterThanMax_);
    }

    function test_Constructor_RevertWhen_FeeRecipientIsZeroAddress() public {
        vm.expectRevert("feeRecipient cannot be address Zero.");
        new NFTBazaar(address(0), feeBps);
    }

    /* setFee */

    // Positive cases

    function test_SetFee_UpdatesFee() public {
        uint16 feeBps_ = 300;

        vm.prank(deployer);
        bazaar.setFee(feeBps_);

        assertEq(bazaar.feeBps(), feeBps_);
    }

    function test_SetFee_AcceptsZero() public {
        uint16 zeroFeeBps_ = 0;

        vm.prank(deployer);
        bazaar.setFee(zeroFeeBps_);

        assertEq(bazaar.feeBps(), zeroFeeBps_);
    }

    function test_SetFee_AcceptsMax() public {
        uint16 feeBps_ = bazaar.MAX_FEE_BPS();

        vm.prank(deployer);
        bazaar.setFee(feeBps_);

        assertEq(bazaar.feeBps(), feeBps_);
    }

    // Events

    function test_SetFee_EmitsFeeSet() public {
        uint16 feeBps_ = 300;

        vm.expectEmit(false, false, false, true);
        emit FeeSet(feeBps_);

        vm.prank(deployer);
        bazaar.setFee(feeBps_);
    }

    // Reverts

    function test_SetFee_RevertWhen_CallerNotOwner() public {
        uint16 feeBps_ = 300;
        
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, randomUser)
        );
        vm.prank(randomUser);
        bazaar.setFee(feeBps_);

        assertEq(bazaar.feeBps(), feeBps);
    }
    
    function test_SetFee_RevertWhen_FeeAboveMax() public {
        uint16 feeBpsGreaterThanMax_ = bazaar.MAX_FEE_BPS() + 1;
        vm.expectRevert("Fee Base Points cannot be greater than 10%.");
        vm.prank(deployer);
        bazaar.setFee(feeBpsGreaterThanMax_);

        assertEq(bazaar.feeBps(), feeBps);
    }

    // Fuzz

    function testFuzz_SetFee_AcceptsFeeUpToMax(uint16 feeBps_) public {
        uint256 max = bazaar.MAX_FEE_BPS();
        feeBps_ = uint16(bound(feeBps_, 0, max));
        
        vm.expectEmit(false, false, false, true);
        emit FeeSet(feeBps_);

        vm.prank(deployer);
        bazaar.setFee(feeBps_);
        
        assertEq(bazaar.feeBps(), feeBps_);
    }

    function testFuzz_SetFee_RevertWhen_FeeAboveMax(uint16 feeBps_) public {
        uint256 max = bazaar.MAX_FEE_BPS();
        feeBps_ = uint16(bound(feeBps_, max + 1, type(uint16).max));

        vm.expectRevert("Fee Base Points cannot be greater than 10%.");
        vm.prank(deployer);
        bazaar.setFee(feeBps_);

        assertEq(bazaar.feeBps(), feeBps);
    }

    /* setFeeRecipient */

    // Positive cases

    function test_SetFeeRecipient_UpdatesRecipient() public {
        address newFeeRecipient_ = makeAddr("newFeeRecipient");
        vm.prank(deployer);
        bazaar.setFeeRecipient(newFeeRecipient_);

        assertEq(bazaar.feeRecipient(), newFeeRecipient_);
    }

    // Events

    function test_SetFeeRecipient_EmitsFeeRecipientSet() public {
        address newFeeRecipient_ = makeAddr("newFeeRecipient");
        vm.expectEmit(true, false, false, true);
        emit FeeRecipientSet(newFeeRecipient_);

        vm.prank(deployer);
        bazaar.setFeeRecipient(newFeeRecipient_);
    }

    // Reverts

    function test_SetFeeRecipient_RevertWhen_CallerNotOwner() public {
        address newFeeRecipient_ = makeAddr("newFeeRecipient");
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, randomUser)
        );

        vm.prank(randomUser);
        bazaar.setFeeRecipient(newFeeRecipient_);

        assertEq(bazaar.feeRecipient(), feeRecipient);
    }

    function test_SetFeeRecipient_RevertWhen_RecipientIsZeroAddress() public {
        vm.expectRevert("feeRecipient cannot be address Zero.");
        vm.prank(deployer);
        bazaar.setFeeRecipient(address(0));

        assertEq(bazaar.feeRecipient(), feeRecipient);
    }

    /* setAllowedToken */

    // Positive cases

    function test_SetAllowedToken_EnablesToken() public { 
        address token_ = address(token);
        assertFalse(bazaar.allowedToken(token_));

        vm.prank(deployer);
        bazaar.setAllowedToken(token_, true);

        assertTrue(bazaar.allowedToken(token_));
    }

    function test_SetAllowedToken_DisablesToken() public {
        address token_ = address(token);
        vm.startPrank(deployer);

        // First, enable token
        bazaar.setAllowedToken(token_, true);
        assertTrue(bazaar.allowedToken(token_));

        // Then, verify it can be desactivated
        bazaar.setAllowedToken(token_, false);
        assertFalse(bazaar.allowedToken(token_)); 

        vm.stopPrank();
    }

    function test_SetAllowedToken_DisablesToken_WhenTokenHasNoCode() public {
        address token_ = address(token);
        vm.startPrank(deployer);

        bazaar.setAllowedToken(token_, true);
        assertTrue(bazaar.allowedToken(token_));

        vm.etch(address(token), "");
        assertEq(token_.code.length, 0);

        bazaar.setAllowedToken(token_, false);
        assertFalse(bazaar.allowedToken(token_));

        vm.stopPrank();
    }

    function test_SetAllowedToken_AcceptsDisablingNonContract() public {
        address wallet_ = makeAddr("eoa");

        vm.prank(deployer);
        bazaar.setAllowedToken(wallet_, false);

        assertFalse(bazaar.allowedToken(wallet_));
    }

    // Events

    function test_SetAllowedToken_EmitsAllowedTokenSet_WhenEnabling() public {
        address token_ = address(token);

        vm.expectEmit(true, false, false, true);
        emit AllowedTokenSet(token_, true);

        vm.prank(deployer);
        bazaar.setAllowedToken(token_, true);
    }

    function test_SetAllowedToken_EmitsAllowedTokenSet_WhenDisabling() public {
        address token_ = address(token);

        vm.startPrank(deployer);
        bazaar.setAllowedToken(token_, true);

        vm.expectEmit(true, false, false, true);
        emit AllowedTokenSet(token_, false);

        bazaar.setAllowedToken(token_, false);
        vm.stopPrank();
    }

    // Reverts

    function test_SetAllowedToken_RevertWhen_EnablingZeroAddress() public {
        vm.expectRevert("Address Zero reserved to ETH.");
        vm.prank(deployer);
        bazaar.setAllowedToken(address(0), true);

        assertFalse(bazaar.allowedToken(address(0)));
    }

    function test_SetAllowedToken_RevertWhen_DisablingZeroAddress() public {
        vm.expectRevert("Address Zero reserved to ETH.");
        vm.prank(deployer);
        bazaar.setAllowedToken(address(0), false);

        assertFalse(bazaar.allowedToken(address(0)));
    }

    function test_SetAllowedToken_RevertWhen_CallerNotOwner() public {
        address token_ = address(token);

        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, randomUser)
        );
        vm.prank(randomUser);
        bazaar.setAllowedToken(token_, true);

        assertFalse(bazaar.allowedToken(token_));
    }

    function test_SetAllowedToken_RevertWhen_EnablingNonContract() public {
        address wallet_ = makeAddr("eoa");

        vm.expectRevert("Not a contract.");
        vm.prank(deployer);
        bazaar.setAllowedToken(wallet_, true);

        assertFalse(bazaar.allowedToken(wallet_));
    }

    /* listNFT */

    // Positive cases

    function test_ListNFT_StoresListing() public {
        uint256 endTime_ = INITIAL_TIMESTAMP + LISTING_DURATION;
        _approveBazaar();

        vm.prank(seller);
        bazaar.listNFT(address(nft), tokenId, address(0), DEFAULT_PRICE, endTime_);

        _assertListing(seller, address(0), DEFAULT_PRICE, INITIAL_TIMESTAMP, endTime_);
    }

    function test_ListNFT_StoresListing_WithAllowedERC20() public {
        uint256 endTime_ = INITIAL_TIMESTAMP + LISTING_DURATION;
        _allowToken();
        _approveBazaar();

        vm.prank(seller);
        bazaar.listNFT(address(nft), tokenId, address(token), DEFAULT_PRICE, endTime_);

        (, address paymentToken_, , , , ) = bazaar.listing(address(nft), tokenId);

        assertEq(paymentToken_, address(token));
    }

    function test_ListNFT_AcceptsEndTimeZero() public {
        uint256 endTime_ = 0;
        _allowToken();
        _approveBazaar();

        vm.prank(seller);
        bazaar.listNFT(address(nft), tokenId, address(0), DEFAULT_PRICE, endTime_);

        (, , , , , uint256 endTime) = bazaar.listing(address(nft), tokenId);

        assertEq(endTime, endTime_);
    }

    function test_ListNFT_StoresListing_WithApprovalForAll() public {
        _approveBazaarForAll();
        assertEq(nft.getApproved(tokenId), address(0));

        vm.prank(seller);
        bazaar.listNFT(address(nft), tokenId, address(0), DEFAULT_PRICE, INITIAL_TIMESTAMP + LISTING_DURATION);

        (address seller_, , , , , ) = bazaar.listing(address(nft), tokenId);
        assertEq(seller_, seller);
    }

    function test_ListNFT_DoesNotTransferNFT() public {
        _approveBazaar();

        vm.prank(seller);
        bazaar.listNFT(address(nft), tokenId, address(0), DEFAULT_PRICE, INITIAL_TIMESTAMP + LISTING_DURATION);

        assertEq(nft.ownerOf(tokenId), seller);
    }

    function test_ListNFT_OverwritesListing_WhenSellerRelists() public {
        _allowToken();
        _approveBazaar();

        vm.startPrank(seller);
        
        bazaar.listNFT(address(nft), tokenId, address(0), DEFAULT_PRICE, INITIAL_TIMESTAMP + LISTING_DURATION);

        vm.warp(INITIAL_TIMESTAMP + 1 days);
        
        uint256 relistPrice_ = DEFAULT_PRICE * 2;
        uint256 newEndTime_ = block.timestamp + LISTING_DURATION;
        bazaar.listNFT(address(nft), tokenId, address(token), relistPrice_, newEndTime_);
        vm.stopPrank();

        _assertListing(seller, address(token), relistPrice_, INITIAL_TIMESTAMP + 1 days, newEndTime_);
    }

    function test_ListNFT_OverwritesListing_WhenNewOwnerLists() public {
        address newOwner_ = makeAddr("newOwner");
        uint256 firstEndTime_ = INITIAL_TIMESTAMP + LISTING_DURATION;

        // 1. The original seller lists
        _approveBazaar();
        vm.startPrank(seller);
        bazaar.listNFT(address(nft), tokenId, address(0), DEFAULT_PRICE, firstEndTime_);
        
        // 2. The seller transfers the NFT : the token approval is deleted
        nft.transferFrom(seller, newOwner_, tokenId);
        assertEq(nft.ownerOf(tokenId), newOwner_);
        assertEq(nft.getApproved(tokenId), address(0));
        vm.stopPrank();

        // 3. The stale listing is still alive
        _assertListing(seller, address(0), DEFAULT_PRICE, INITIAL_TIMESTAMP, firstEndTime_);

        // 4. The new owner approves the bazaar and lists at another price, later in time
        uint256 newStartTime_ = INITIAL_TIMESTAMP + 1 days;
        uint256 newEndTime_ = newStartTime_ + LISTING_DURATION;
        vm.warp(newStartTime_);
        _approveBazaar(newOwner_, tokenId);

        vm.prank(newOwner_);
        bazaar.listNFT(address(nft), tokenId, address(0), 20, newEndTime_);

        // 5. The stale listing was overwritten
        _assertListing(newOwner_, address(0), 20, newStartTime_, newEndTime_);
    }

    // Events

    function test_ListNFT_EmitsNFTListed() public {
        uint256 endTime_ = INITIAL_TIMESTAMP + LISTING_DURATION;
        _approveBazaar();
        vm.expectEmit(true, true, true, true);
        emit NFTListed(seller, address(nft), tokenId, address(0), DEFAULT_PRICE, endTime_);

        vm.prank(seller);
        bazaar.listNFT(address(nft), tokenId, address(0), DEFAULT_PRICE, endTime_);
    }

    // Fuzz

    function testFuzz_ListNFT_StoresListing_WithAnyPriceAndValidEndTime(uint256 price_, uint256 endTime_) public {
        price_ = bound(price_, 1, type(uint256).max);
        endTime_ = bound(endTime_, INITIAL_TIMESTAMP + 1, type(uint256).max);
        _approveBazaar();

        vm.expectEmit(true, true, true, true);
        emit NFTListed(seller, address(nft), tokenId, address(0), price_, endTime_);

        vm.prank(seller);
        bazaar.listNFT(address(nft), tokenId, address(0), price_, endTime_);

        _assertListing(seller, address(0), price_, INITIAL_TIMESTAMP, endTime_);
    }

    // Reverts

    function test_ListNFT_RevertWhen_PriceIsZero() public {
        uint256 endTime_ = block.timestamp + LISTING_DURATION;
        address paymentToken_ = address(0);

        vm.expectRevert("Price cannot be 0.");
        vm.prank(seller);
        bazaar.listNFT(address(nft), tokenId, paymentToken_, 0, endTime_);

        _assertNoListing();
    }

    function test_ListNFT_RevertWhen_CallerIsNotOwner() public {
        uint256 endTime_ = block.timestamp + LISTING_DURATION;
        address paymentToken_ = address(0);

        vm.expectRevert("You are not the owner of the NFT.");
        vm.prank(randomUser);
        bazaar.listNFT(address(nft), tokenId, paymentToken_, DEFAULT_PRICE, endTime_);

        _assertNoListing();
    }

    function test_ListNFT_RevertWhen_ApprovedToAnotherAddress() public {
        uint256 endTime_ = block.timestamp + LISTING_DURATION;

        vm.prank(seller);
        nft.approve(randomUser, tokenId);

        vm.expectRevert("The contract has not been approved.");
        vm.prank(seller);
        bazaar.listNFT(address(nft), tokenId, address(0), DEFAULT_PRICE, endTime_);

        _assertNoListing();
    }

    function test_ListNFT_RevertWhen_NoApproval() public {
        uint256 endTime_ = block.timestamp + LISTING_DURATION;

        vm.expectRevert("The contract has not been approved.");
        vm.prank(seller);
        bazaar.listNFT(address(nft), tokenId, address(0), DEFAULT_PRICE, endTime_);

        _assertNoListing();
    }

    function test_ListNFT_RevertWhen_PaymentTokenNotAllowed() public {
        uint256 endTime_ = block.timestamp + LISTING_DURATION;
        address notAllowedToken_ = makeAddr("notAllowedToken");
        _approveBazaar();

        vm.expectRevert("This payment method is not allowed.");
        vm.prank(seller);
        bazaar.listNFT(address(nft), tokenId, notAllowedToken_, DEFAULT_PRICE, endTime_);

        _assertNoListing();
    }

    function test_ListNFT_RevertWhen_EndTimeLowerThanNow() public {
        uint256 endTime_ = block.timestamp - 1;
        address paymentToken_ = address(0);
        _approveBazaar();

        vm.expectRevert("End time not valid.");
        vm.prank(seller);
        bazaar.listNFT(address(nft), tokenId, paymentToken_, DEFAULT_PRICE, endTime_);

        _assertNoListing();
    }

    function test_ListNFT_RevertWhen_EndTimeIsNow() public {
        uint256 endTime_ = block.timestamp;
        address paymentToken_ = address(0);
        _approveBazaar();

        vm.expectRevert("End time not valid.");
        vm.prank(seller);
        bazaar.listNFT(address(nft), tokenId, paymentToken_, DEFAULT_PRICE, endTime_);

        _assertNoListing();
    }

    /* cancelListing */

    // Positive cases

    function test_CancelListing_DeletesListing() public {
        uint256 endTime_ = INITIAL_TIMESTAMP + LISTING_DURATION;
        _listDefault();
        _assertListing(seller, address(0), DEFAULT_PRICE, INITIAL_TIMESTAMP, endTime_);

        vm.prank(seller);
        bazaar.cancelListing(address(nft), tokenId);

        _assertNoListing();
    }

    function test_CancelListing_DeletesListing_WhenListingExpired() public {
        uint256 endTime_ = INITIAL_TIMESTAMP + LISTING_DURATION;
        _listDefault();
        _assertListing(seller, address(0), DEFAULT_PRICE, INITIAL_TIMESTAMP, endTime_);

        vm.warp(endTime_ + 1);
        vm.prank(seller);
        bazaar.cancelListing(address(nft), tokenId);

        _assertNoListing();
    }

    function test_CancelListing_DoesNotAffectOtherListings() public {
        uint256 endTime_ = INITIAL_TIMESTAMP + LISTING_DURATION;

        // Listing #1
        _listDefault();

        // Listing #2
        uint256 token2Id_ = tokenId + 1;
        nft.mint(seller, token2Id_);
        _approveBazaar(seller, token2Id_);

        vm.prank(seller);
        bazaar.listNFT(address(nft), token2Id_, address(0), DEFAULT_PRICE, endTime_);

        // Cancel Listing #1
        vm.prank(seller);
        bazaar.cancelListing(address(nft), tokenId);

        // Assert Listing #1 cancelled
        _assertNoListing();

        // Assert Listing #2 still alive
        (address seller2_, , , , , ) = bazaar.listing(address(nft), token2Id_);
        assertEq(seller2_, seller);
    }

    function test_CancelListing_AllowsRelisting() public {
        uint256 endTime_ = INITIAL_TIMESTAMP + LISTING_DURATION;
        _listDefault();
        _assertListing(seller, address(0), DEFAULT_PRICE, INITIAL_TIMESTAMP, endTime_);

        vm.prank(seller);
        bazaar.cancelListing(address(nft), tokenId);

        _assertNoListing();

        _listDefault();
        _assertListing(seller, address(0), DEFAULT_PRICE, INITIAL_TIMESTAMP, endTime_);
    }

    // Events

    function test_CancelListing_EmitsNFTCancelled() public {
        _listDefault();
        vm.expectEmit(true, true, true, false);
        emit NFTCancelled(seller, address(nft), tokenId);

        vm.prank(seller);
        bazaar.cancelListing(address(nft), tokenId);
    }

    // Reverts

    function test_CancelListing_RevertWhen_ListingDoesNotExist() public {
        vm.expectRevert("Listing does not exist.");
        vm.prank(seller);
        bazaar.cancelListing(address(nft), tokenId);
    }

    function test_CancelListing_RevertWhen_CallerNotSeller() public {
        _listDefault();
        vm.expectRevert("Not listing's seller.");
        vm.prank(randomUser);
        bazaar.cancelListing(address(nft), tokenId);
    }

    function test_CancelListing_RevertWhen_AlreadyCancelled() public {
        _listDefault();
        vm.startPrank(seller);
        
        bazaar.cancelListing(address(nft), tokenId);
        vm.expectRevert("Listing does not exist.");
        bazaar.cancelListing(address(nft), tokenId);

        vm.stopPrank();
    }

    function test_CancelListing_RevertWhen_CallerIsNewOwnerOfStaleListing() public {
        address newOwner_ = makeAddr("newOwner");
        uint256 firstEndTime_ = INITIAL_TIMESTAMP + LISTING_DURATION;
        
        // 1. The original seller lists
        _listDefault();

        // 2. The seller transfers the NFT : the token approval is deleted
        vm.prank(seller);
        nft.transferFrom(seller, newOwner_, tokenId);
        assertEq(nft.ownerOf(tokenId), newOwner_);
        assertEq(nft.getApproved(tokenId), address(0));

        // 3. The stale listing is still alive
        _assertListing(seller, address(0), DEFAULT_PRICE, INITIAL_TIMESTAMP, firstEndTime_);

        // 4. The new owner cannot cancel it: only the listed seller can
        vm.expectRevert("Not listing's seller.");
        vm.prank(newOwner_);
        bazaar.cancelListing(address(nft), tokenId);
    }
    
    /* Ownable2Step */

    // Positive cases

    function test_TransferOwnership_KeepsOwnerUntilAccepted() public {
        address newOwner_ = makeAddr("newOwner");

        vm.prank(deployer);
        bazaar.transferOwnership(newOwner_);

        // The transfer is only started: nothing has changed yet
        assertEq(bazaar.pendingOwner(), newOwner_);
        assertEq(bazaar.owner(), deployer);
        
        // The pending owner still cannot administer
        uint16 feeBps_ = 300;
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, newOwner_)
        );
        vm.prank(newOwner_);
        bazaar.setFee(feeBps_);
    }

    function test_AcceptOwnership_CompletesTransfer() public {
        address newOwner_ = makeAddr("newOwner");

        vm.prank(deployer);
        bazaar.transferOwnership(newOwner_);

        vm.prank(newOwner_);
        bazaar.acceptOwnership();
        
         // The new owner can administer
        uint16 feeBps_ = 300;
        vm.prank(newOwner_);
        bazaar.setFee(feeBps_);
        assertEq(bazaar.feeBps(), feeBps_);

        // The previous owner no longer can
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, deployer)
        );
        vm.prank(deployer);
        bazaar.setFee(feeBps_);
    }
    
    // Reverts

    function test_AcceptOwnership_RevertWhen_CallerNotPendingOwner() public {
        address newOwner_ = makeAddr("newOwner");

        vm.prank(deployer);
        bazaar.transferOwnership(newOwner_);

        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, randomUser)
        );
        vm.prank(randomUser);
        bazaar.acceptOwnership();
    }
    
    function test_TransferOwnership_RevertWhen_CallerNotOwner() public {
        address newOwner_ = makeAddr("newOwner");
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, randomUser)
        );
        vm.prank(randomUser);
        bazaar.transferOwnership(newOwner_);        
    }

    function _allowToken() internal {
        vm.prank(deployer);
        bazaar.setAllowedToken(address(token), true);
    }

    function _approveBazaar() internal {
        vm.prank(seller);
        nft.approve(address(bazaar), tokenId);
    }

    function _approveBazaar(address owner_, uint256 tokenId_) internal {
        vm.prank(owner_);
        nft.approve(address(bazaar), tokenId_);
    }

    function _assertNoListing() internal view {
        (address seller_, , , , , ) = bazaar.listing(address(nft), tokenId);
        assertEq(seller_, address(0));
    }

    function _assertListing(address seller_, address paymentToken_, uint256 price_, uint256 startTime_, uint256 endTime_) internal view {
        (
            address gotSeller,
            address gotToken,
            uint256 gotStartPrice,
            uint256 gotEndPrice,
            uint256 gotStartTime,
            uint256 gotEndTime
        ) = bazaar.listing(address(nft), tokenId);

        assertEq(gotSeller, seller_);
        assertEq(gotToken, paymentToken_);
        assertEq(gotStartPrice, price_);
        assertEq(gotEndPrice, price_);
        assertEq(gotStartTime, startTime_);
        assertEq(gotEndTime, endTime_);
    }

    function _approveBazaarForAll() internal {
        vm.prank(seller);
        nft.setApprovalForAll(address(bazaar), true);
    }

    function _listDefault() internal {
        _approveBazaar();
        vm.prank(seller);
        bazaar.listNFT(address(nft), tokenId, address(0), DEFAULT_PRICE, INITIAL_TIMESTAMP + LISTING_DURATION);
    }
}