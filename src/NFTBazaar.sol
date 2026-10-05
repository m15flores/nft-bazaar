// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

import "@openzeppelin/contracts/access/Ownable2Step.sol";

contract NFTBazaar is Ownable2Step {

    struct Listing {
        address seller;
        address paymentToken;
        uint256 startPrice;
        uint256 endPrice;
        uint256 startTime;
        uint256 endTime;
    }

    mapping(address => mapping(uint256 => Listing)) public listing;

    uint16 public feeBps;
    uint16 public constant MAX_FEE_BPS = 1000;
    address public feeRecipient;
    mapping(address => bool) public allowedToken;
    mapping(address => uint256) public pendingEth;

    event FeeSet(uint16 feeBps_);
    event FeeRecipientSet(address indexed feeRecipient_);
    event AllowedTokenSet(address indexed token_, bool allowed_);

    constructor(address feeRecipient_, uint16 feeBps_) Ownable(msg.sender) {
        _setFee(feeBps_);
        _setFeeRecipient(feeRecipient_);
    }

    function setFee(uint16 feeBps_) external onlyOwner {
        _setFee(feeBps_);
    }

    function setFeeRecipient(address feeRecipient_) external onlyOwner {
        _setFeeRecipient(feeRecipient_);
    }

    function setAllowedToken(address token_, bool allowed_) external onlyOwner {
        require(token_ != address(0), "Address Zero reserved to ETH.");
        allowedToken[token_] = allowed_;

        emit AllowedTokenSet(token_, allowed_);
    }

    function _setFee(uint16 feeBps_) internal {
        require(feeBps_ <= MAX_FEE_BPS, "Fee Base Points cannot be greater than 10%.");
        feeBps = feeBps_;

        emit FeeSet(feeBps_);
    }

    function _setFeeRecipient(address feeRecipient_) internal {
        require(feeRecipient_ != address(0), "feeRecipient cannot be address Zero.");
        feeRecipient = feeRecipient_;

        emit FeeRecipientSet(feeRecipient_);
    }
}