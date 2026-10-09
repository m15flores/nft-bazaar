// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

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

    event FeeSet(uint16 feeBps);
    event FeeRecipientSet(address indexed feeRecipient);
    event AllowedTokenSet(address indexed token, bool allowed);
    event NFTListed(address indexed seller, address indexed nft, uint256 indexed tokenId, address paymentToken, uint256 price, uint256 endTime);
    event NFTCancelled(address indexed seller, address indexed nft, uint256 indexed tokenId);
    event NFTListingUpdated(address indexed seller, address indexed nft, uint256 indexed tokenId, uint256 oldPrice, uint256 newPrice);
    event NFTSold(address indexed buyer, address indexed seller, address indexed nft, uint256 tokenId, address paymentToken, uint256 price);

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
        require(!allowed_ || token_.code.length > 0, "Not a contract.");

        allowedToken[token_] = allowed_;

        emit AllowedTokenSet(token_, allowed_);
    }

    function listNFT(address nft_, uint256 tokenId_, address paymentToken_, uint256 price_, uint256 endTime_) external {
        require(price_ > 0, "Price cannot be 0.");
        address owner_ = IERC721(nft_).ownerOf(tokenId_);
        require(owner_ == msg.sender, "You are not the owner of the NFT.");
        require(IERC721(nft_).getApproved(tokenId_) == address(this) || IERC721(nft_).isApprovedForAll(owner_, address(this)), "The contract has not been approved.");
        require(paymentToken_ == address(0) || allowedToken[paymentToken_], "This payment method is not allowed.");
        require(endTime_ == 0 || endTime_ > block.timestamp, "End time not valid.");

        Listing memory listing_ = Listing({
            seller: msg.sender,
            paymentToken: paymentToken_,
            startPrice: price_,
            endPrice: price_,
            startTime: block.timestamp,
            endTime: endTime_
        });

        listing[nft_][tokenId_] = listing_;

        emit NFTListed(msg.sender, nft_, tokenId_, paymentToken_, price_, endTime_);
    }

    function cancelListing(address nft_, uint256 tokenId_) external {
        _getSellerListing(nft_, tokenId_);

        delete listing[nft_][tokenId_];

        emit NFTCancelled(msg.sender, nft_, tokenId_);
    }

    function updatePrice(address nft_, uint256 tokenId_, uint256 newPrice_) external {
        Listing storage listing_ = _getSellerListing(nft_, tokenId_);
        require(newPrice_ > 0, "New price cannot be 0.");

        uint256 oldPrice_ = listing_.startPrice;

        listing_.startPrice = newPrice_;
        listing_.endPrice = newPrice_;

        emit NFTListingUpdated(msg.sender, nft_, tokenId_, oldPrice_, newPrice_);
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

    function _getSellerListing(address nft_, uint256 tokenId_) internal view returns (Listing storage listing_){
        listing_ = listing[nft_][tokenId_];
        require(listing_.seller != address(0), "Listing does not exist.");
        require(listing_.seller == msg.sender, "Not listing's seller.");
    }

    function _computeSplit(address nft_, uint256 tokenId_, uint256 price_) internal view returns (uint256 fee, address royaltyReceiver, uint256 royalty, uint256 proceeds) {
        fee = (price_ * feeBps) / 10_000;
        
        if(ERC165Checker.supportsInterface(nft_, type(IERC2981).interfaceId)) {
            (royaltyReceiver, royalty) = IERC2981(nft_).royaltyInfo(tokenId_, price_);
            if(royaltyReceiver == address(0)) royalty = 0;
        }
        require(royalty <= price_ - fee, "Fee plus royalty exceed price.");
        proceeds = price_ - fee - royalty;
    }

    function _settle(address nft_, uint256 tokenId_, address seller_, address buyer_, address paymentToken_, uint256 price_) internal {
        (uint256 fee, address royaltyReceiver, uint256 royalty, uint256 proceeds) = _computeSplit(nft_, tokenId_, price_);
        
        pendingEth[seller_] += proceeds;
        pendingEth[feeRecipient] += fee;
        if(royalty > 0) pendingEth[royaltyReceiver] += royalty;

        IERC721(nft_).safeTransferFrom(seller_, buyer_, tokenId_);

        emit NFTSold(buyer_, seller_, nft_, tokenId_, paymentToken_, price_);
    }
}