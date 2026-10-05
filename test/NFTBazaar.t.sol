// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

import "forge-std/Test.sol";
import "../src/NFTBazaar.sol";

contract NFTBazaarTest is Test {
    
    NFTBazaar bazaar;
    address deployer;
    address feeRecipient;
    uint16 feeBps;
    address randomUser;

    event FeeSet(uint16 feeBps_);
    event FeeRecipientSet(address indexed feeRecipient_);
    event AllowedTokenSet(address indexed token_, bool allowed_);

    function setUp() public {
        deployer = makeAddr("deployer");
        feeRecipient = makeAddr("feeRecipient");
        feeBps = 250;
        randomUser = makeAddr("randomUser");
        
        vm.prank(deployer);
        bazaar = new NFTBazaar(feeRecipient, feeBps);
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
        address token_ = makeAddr("token");
        assertFalse(bazaar.allowedToken(token_));

        vm.prank(deployer);
        bazaar.setAllowedToken(token_, true);

        assertTrue(bazaar.allowedToken(token_));
    }

    function test_SetAllowedToken_DisablesToken() public {
        address token_ = makeAddr("token");
        vm.startPrank(deployer);

        // First, enable token
        bazaar.setAllowedToken(token_, true);
        assertTrue(bazaar.allowedToken(token_));

        // Then, verify it can be desactivated
        bazaar.setAllowedToken(token_, false);
        assertFalse(bazaar.allowedToken(token_)); 

        vm.stopPrank();
    }

    // Events

    function test_SetAllowedToken_EmitsAllowedTokenSet_WhenEnabling() public {
        address token_ = makeAddr("token");

        vm.expectEmit(true, false, false, true);
        emit AllowedTokenSet(token_, true);

        vm.prank(deployer);
        bazaar.setAllowedToken(token_, true);
    }

    function test_SetAllowedToken_EmitsAllowedTokenSet_WhenDisabling() public {
        address token_ = makeAddr("token");

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

    // address == 0 reverts with false
    function test_SetAllowedToken_RevertWhen_DisablingZeroAddress() public {
        vm.expectRevert("Address Zero reserved to ETH.");
        vm.prank(deployer);
        bazaar.setAllowedToken(address(0), false);

        assertFalse(bazaar.allowedToken(address(0)));
    }

    function test_SetAllowedToken_RevertWhen_CallerNotOwner() public {
        address token_ = makeAddr("token");

        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, randomUser)
        );
        vm.prank(randomUser);
        bazaar.setAllowedToken(token_, true);

        assertFalse(bazaar.allowedToken(token_));
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

    function test_RevertWhen_AcceptOwnershipCallerNotPendingOwner() public {
        address newOwner_ = makeAddr("newOwner");

        vm.prank(deployer);
        bazaar.transferOwnership(newOwner_);

        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, randomUser)
        );
        vm.prank(randomUser);
        bazaar.acceptOwnership();
    }
    
    function test_RevertWhen_TransferOwnershipCallerNotOwner() public {
        address newOwner_ = makeAddr("newOwner");
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, randomUser)
        );
        vm.prank(randomUser);
        bazaar.transferOwnership(newOwner_);        
    }
    
}