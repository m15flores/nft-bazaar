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

    // Set up Tests

    function test_RevertWhen_FeeBpsGreaterThanMaxFeeBps() public {
        uint16 feeBpsGreaterThanMax_ = bazaar.MAX_FEE_BPS() + 1;
        vm.expectRevert("Fee Base Points cannot be greater than 10%.");
        new NFTBazaar(feeRecipient, feeBpsGreaterThanMax_);
    }

    function test_RevertWhen_FeeRecipientIsAddressZero() public {
        vm.expectRevert("feeRecipient cannot be address Zero.");
        new NFTBazaar(address(0), feeBps);
    }

    function test_SetUpInitsCorrectly() public view {
        assertEq(bazaar.owner(), deployer);
        assertEq(bazaar.feeRecipient(), feeRecipient);
        assertEq(bazaar.feeBps(), feeBps);
    }

    function test_SetUpInitsCorrectlyWithMaxFee() public {
        uint16 maxFee_ = bazaar.MAX_FEE_BPS();   // leer la constante antes del prank

        vm.prank(deployer);
        NFTBazaar bazaarMax_ = new NFTBazaar(feeRecipient, maxFee_);

        assertEq(bazaarMax_.feeBps(), maxFee_);
    }

    function test_EmitsFeeSet() public {
        vm.expectEmit(false, false, false, true);
        emit FeeSet(feeBps);

        vm.prank(deployer);
        new NFTBazaar(feeRecipient, feeBps);
    }

    function test_EmitsFeeRecipientSet() public {
        vm.expectEmit(true, false, false, true);
        emit FeeRecipientSet(feeRecipient);

        vm.prank(deployer);
        new NFTBazaar(feeRecipient, feeBps);
    }

    // setFee

    // failes when no owner
    function test_RevertWhen_SetFeeCallerNotOwner() public {
        uint16 feeBps_ = 300;
        
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, randomUser)
        );
        vm.prank(randomUser);
        bazaar.setFee(feeBps_);

        assertEq(bazaar.feeBps(), feeBps);
    }

    // failes when > max_fee

    function test_RevertWhen_SetFeeFeeBpsGreaterThanMaxFeeBps() public {
        uint16 feeBpsGreaterThanMax_ = bazaar.MAX_FEE_BPS() + 1;
        vm.expectRevert("Fee Base Points cannot be greater than 10%.");
        vm.prank(deployer);
        bazaar.setFee(feeBpsGreaterThanMax_);

        assertEq(bazaar.feeBps(), feeBps);
    }

    // green
    function test_SetFee() public {
        uint16 feeBps_ = 300;

        vm.prank(deployer);
        bazaar.setFee(feeBps_);

        assertEq(bazaar.feeBps(), feeBps_);
    }

    function test_SetFeeWorksWithMax() public {
        uint16 feeBps_ = bazaar.MAX_FEE_BPS();

        vm.prank(deployer);
        bazaar.setFee(feeBps_);

        assertEq(bazaar.feeBps(), feeBps_);
    }

    // green - emits event
    function test_SetFeeEmitsFeeSet() public {
        uint16 feeBps_ = 300;

        vm.expectEmit(false, false, false, true);
        emit FeeSet(feeBps_);

        vm.prank(deployer);
        bazaar.setFee(feeBps_);
    }

    function test_SetFeeZeroFeeBps() public {
        uint16 zeroFeeBps_ = 0;

        vm.prank(deployer);
        bazaar.setFee(zeroFeeBps_);

        assertEq(bazaar.feeBps(), zeroFeeBps_);
    }

    function testFuzz_SetFee(uint16 feeBps_) public {
        uint256 max = bazaar.MAX_FEE_BPS();
        feeBps_ = uint16(bound(feeBps_, 0, max));
        
        vm.expectEmit(false, false, false, true);
        emit FeeSet(feeBps_);

        vm.prank(deployer);
        bazaar.setFee(feeBps_);
        
        assertEq(bazaar.feeBps(), feeBps_);
    }

    function testFuzz_SetFee_RevertWhen_FeeBpsGreaterThanMax(uint16 feeBps_) public {
        uint256 max = bazaar.MAX_FEE_BPS();
        feeBps_ = uint16(bound(feeBps_, max + 1, type(uint16).max));

        vm.expectRevert("Fee Base Points cannot be greater than 10%.");
        vm.prank(deployer);
        bazaar.setFee(feeBps_);

        assertEq(bazaar.feeBps(), feeBps);
    }

    // setFeeRecipient

    // failes when no owner
    function test_RevertWhen_SetFeeRecipientCallerNotOwner() public {
        address newFeeRecipient_ = makeAddr("newFeeRecipient");
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, randomUser)
        );

        vm.prank(randomUser);
        bazaar.setFeeRecipient(newFeeRecipient_);

        assertEq(bazaar.feeRecipient(), feeRecipient);
    }

    // failes when ==  address 0
    function test_RevertWhen_SetFeeRecipientFeeRecipientIsAddressZero() public {
        vm.expectRevert("feeRecipient cannot be address Zero.");
        vm.prank(deployer);
        bazaar.setFeeRecipient(address(0));

        assertEq(bazaar.feeRecipient(), feeRecipient);
    }

    // green
    function test_SetFeeRecipient() public {
        address newFeeRecipient_ = makeAddr("newFeeRecipient");
        vm.prank(deployer);
        bazaar.setFeeRecipient(newFeeRecipient_);

        assertEq(bazaar.feeRecipient(), newFeeRecipient_);
    }

    // green - emits event
    function test_SetFeeRecipientEmitsFeeRecipientSet() public {
        address newFeeRecipient_ = makeAddr("newFeeRecipient");
        vm.expectEmit(true, false, false, true);
        emit FeeRecipientSet(newFeeRecipient_);

        vm.prank(deployer);
        bazaar.setFeeRecipient(newFeeRecipient_);
    }

    // setAllowedToken

    // address == 0 reverts with true
    function test_RevertWhen_SetAllowedTokenWithAllowedToTrueAndTokenIsAddressZero() public {
        vm.expectRevert("Address Zero reserved to ETH.");
        vm.prank(deployer);
        bazaar.setAllowedToken(address(0), true);

        assertFalse(bazaar.allowedToken(address(0)));
    }

    // address == 0 reverts with false
    function test_RevertWhen_SetAllowedTokenWithAllowedToFalseAndTokenIsAddressZero() public {
        vm.expectRevert("Address Zero reserved to ETH.");
        vm.prank(deployer);
        bazaar.setAllowedToken(address(0), false);

        assertFalse(bazaar.allowedToken(address(0)));
    }


    // no owner reverts
    function test_RevertWhen_SetAllowedTokenCallerNotOwner() public {
        address token_ = makeAddr("token");

        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, randomUser)
        );
        vm.prank(randomUser);
        bazaar.setAllowedToken(token_, true);

        assertFalse(bazaar.allowedToken(token_));
    }

    // green test con true
    function test_SetAllowedTokenWithAllowedToTrue() public { 
        address token_ = makeAddr("token");
        assertFalse(bazaar.allowedToken(token_));

        vm.prank(deployer);
        bazaar.setAllowedToken(token_, true);

        assertTrue(bazaar.allowedToken(token_));
    }

    // green test con false
    function test_SetAllowedTokenWithAllowedToFalse() public {
        // First, we activate the allowance to the token
        address token_ = makeAddr("token");

        vm.startPrank(deployer);

        bazaar.setAllowedToken(token_, true);

        // Then, we verify it can be desactivated
        assertTrue(bazaar.allowedToken(token_));

        bazaar.setAllowedToken(token_, false);

        assertFalse(bazaar.allowedToken(token_)); 

        vm.stopPrank();
    }

    function test_SetAllowedTokenWithAllowedToTrueEmitsAllowedTokenSet() public {
        address token_ = makeAddr("token");

        vm.expectEmit(true, false, false, true);
        emit AllowedTokenSet(token_, true);

        vm.prank(deployer);
        bazaar.setAllowedToken(token_, true);
    }

    function test_SetAllowedTokenWithAllowedToFalseEmitsAllowedTokenSet() public {
        address token_ = makeAddr("token");

        vm.startPrank(deployer);
        bazaar.setAllowedToken(token_, true);

        vm.expectEmit(true, false, false, true);
        emit AllowedTokenSet(token_, false);

        bazaar.setAllowedToken(token_, false);
        vm.stopPrank();
    }

    // Ownable2Step
    function test_TransferOwnership_KeepsOwnerUntilAccepted() public {
        address newOwner_ = makeAddr("newOwner");

        vm.prank(deployer);
        bazaar.transferOwnership(newOwner_);

        assertEq(bazaar.pendingOwner(), newOwner_);
        assertEq(bazaar.owner(), deployer);
        
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
        
        uint16 feeBps_ = 300;
        vm.prank(newOwner_);
        bazaar.setFee(feeBps_);
        assertEq(bazaar.feeBps(), feeBps_);
    }
    
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