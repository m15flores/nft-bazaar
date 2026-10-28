// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @notice Fixed-price marketplace for ERC721 tokens, paid in ETH or in owner-allowed ERC20 tokens.
 * @dev Each sale pays a marketplace fee (`feeBps` of the price, rounded down), an ERC2981 royalty if the
 * collection reports one, and the remainder to the seller, so rounding dust goes to the seller.
 * ETH is credited to `pendingEth` and claimed with {withdraw} or {withdrawFor}; ERC20 is transferred
 * directly from the buyer to each recipient, so the contract never holds tokens.
 */
contract NFTBazaar is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Listing {
        address seller;
        address paymentToken;
        uint256 price;
        uint256 endTime;
    }

    mapping(address => mapping(uint256 => Listing)) public listing;

    uint16 public feeBps;
    address public feeRecipient;
    mapping(address => bool) public allowedToken;
    mapping(address => uint256) public pendingEth;

    uint16 public constant MAX_FEE_BPS = 1000;
    uint256 public constant BPS_DENOMINATOR = 10_000;

    /**
     * @dev Emitted when the marketplace fee is set to `feeBps`.
     */
    event FeeSet(uint16 feeBps);

    /**
     * @dev Emitted when the fee recipient is set to `feeRecipient`.
     */
    event FeeRecipientSet(address indexed feeRecipient);

    /**
     * @dev Emitted when ERC20 `token` is allowed or disallowed as payment.
     */
    event AllowedTokenSet(address indexed token, bool allowed);

    /**
     * @dev Emitted when `seller` lists `tokenId` of `nft` for `price` in `paymentToken` until `endTime`.
     */
    event NFTListed(
        address indexed seller,
        address indexed nft,
        uint256 indexed tokenId,
        address paymentToken,
        uint256 price,
        uint256 endTime
    );

    /**
     * @dev Emitted when `seller` cancels the listing of `tokenId` of `nft`.
     */
    event NFTCancelled(address indexed seller, address indexed nft, uint256 indexed tokenId);

    /**
     * @dev Emitted when `seller` changes the price of a listing from `oldPrice` to `newPrice`.
     */
    event NFTListingUpdated(
        address indexed seller, address indexed nft, uint256 indexed tokenId, uint256 oldPrice, uint256 newPrice
    );

    /**
     * @dev Emitted when `buyer` buys `tokenId` of `nft` from `seller` for `price` in `paymentToken`.
     */
    event NFTSold(
        address indexed buyer,
        address indexed seller,
        address indexed nft,
        uint256 tokenId,
        address paymentToken,
        uint256 price
    );

    /**
     * @dev Emitted when `amount` of pending ETH is paid out to `account`.
     */
    event Withdrawn(address indexed account, uint256 amount);

    /**
     * @notice Sets the deployer as owner and initializes the marketplace fee and its recipient.
     * @param feeRecipient_ Address that receives marketplace fees. Cannot be the zero address.
     * @param feeBps_ Marketplace fee in basis points. Cannot exceed `MAX_FEE_BPS`.
     */
    constructor(address feeRecipient_, uint16 feeBps_) Ownable(msg.sender) {
        _setFee(feeBps_);
        _setFeeRecipient(feeRecipient_);
    }

    /**
     * @notice Sets the marketplace fee applied to future sales.
     * @param feeBps_ New fee in basis points. Cannot exceed `MAX_FEE_BPS`.
     */
    function setFee(uint16 feeBps_) external onlyOwner {
        _setFee(feeBps_);
    }

    /**
     * @notice Sets the address that receives marketplace fees from future sales.
     * @param feeRecipient_ New fee recipient. Cannot be the zero address.
     */
    function setFeeRecipient(address feeRecipient_) external onlyOwner {
        _setFeeRecipient(feeRecipient_);
    }

    /**
     * @notice Allows or disallows an ERC20 token as a payment method.
     * @param token_ ERC20 token address. Cannot be the zero address, which represents ETH.
     * @param allowed_ Whether the token is allowed. When true, `token_` must be a contract.
     */
    function setAllowedToken(address token_, bool allowed_) external onlyOwner {
        require(token_ != address(0), "Address Zero reserved to ETH.");
        require(!allowed_ || token_.code.length > 0, "Not a contract.");

        allowedToken[token_] = allowed_;

        emit AllowedTokenSet(token_, allowed_);
    }

    /**
     * @notice Lists an ERC721 token owned by the caller for sale at a fixed price.
     * @dev The token stays with the seller; the contract must be approved for it. Listing the same
     * token again overwrites the previous listing.
     * @param nft_ ERC721 contract address.
     * @param tokenId_ Token to list.
     * @param paymentToken_ ERC20 token used for payment, or the zero address for ETH.
     * @param price_ Sale price in `paymentToken_` units. Must be greater than zero.
     * @param endTime_ Timestamp after which the listing can no longer be bought, or 0 for no expiry.
     */
    function listNFT(address nft_, uint256 tokenId_, address paymentToken_, uint256 price_, uint256 endTime_) external {
        require(price_ > 0, "Price cannot be 0.");
        address owner_ = IERC721(nft_).ownerOf(tokenId_);
        require(owner_ == msg.sender, "You are not the owner of the NFT.");
        require(
            IERC721(nft_).getApproved(tokenId_) == address(this)
                || IERC721(nft_).isApprovedForAll(owner_, address(this)),
            "The contract has not been approved."
        );
        require(paymentToken_ == address(0) || allowedToken[paymentToken_], "This payment method is not allowed.");
        require(endTime_ == 0 || endTime_ > block.timestamp, "End time not valid.");

        Listing memory listing_ =
            Listing({seller: msg.sender, paymentToken: paymentToken_, price: price_, endTime: endTime_});

        listing[nft_][tokenId_] = listing_;

        emit NFTListed(msg.sender, nft_, tokenId_, paymentToken_, price_, endTime_);
    }

    /**
     * @notice Cancels the caller's listing.
     * @param nft_ ERC721 contract address.
     * @param tokenId_ Listed token.
     */
    function cancelListing(address nft_, uint256 tokenId_) external {
        _getSellerListing(nft_, tokenId_);

        delete listing[nft_][tokenId_];

        emit NFTCancelled(msg.sender, nft_, tokenId_);
    }

    /**
     * @notice Changes the price of the caller's listing.
     * @param nft_ ERC721 contract address.
     * @param tokenId_ Listed token.
     * @param newPrice_ New price in the listing's payment token. Must be greater than zero.
     */
    function updatePrice(address nft_, uint256 tokenId_, uint256 newPrice_) external {
        Listing storage listing_ = _getSellerListing(nft_, tokenId_);
        require(newPrice_ > 0, "New price cannot be 0.");

        uint256 oldPrice_ = listing_.price;

        listing_.price = newPrice_;

        emit NFTListingUpdated(msg.sender, nft_, tokenId_, oldPrice_, newPrice_);
    }

    /**
     * @notice Buys a listed token at its current price.
     * @dev `maxPrice_` and `expectedToken_` protect the buyer against a price or payment token change
     * before the transaction is mined. The listing is deleted before any payment or transfer.
     * @param nft_ ERC721 contract address.
     * @param tokenId_ Listed token.
     * @param maxPrice_ Highest price the buyer accepts.
     * @param expectedToken_ Payment token the buyer expects, or the zero address for ETH.
     */
    function buyNFT(address nft_, uint256 tokenId_, uint256 maxPrice_, address expectedToken_)
        external
        payable
        nonReentrant
    {
        Listing memory listing_ = listing[nft_][tokenId_];
        require(listing_.seller != address(0), "Listing does not exist.");
        require(listing_.endTime == 0 || block.timestamp < listing_.endTime, "Listing expired.");
        require(listing_.price <= maxPrice_, "Price above maximum.");
        require(listing_.paymentToken == expectedToken_, "Payment token mismatch.");

        if (listing_.paymentToken == address(0)) {
            require(msg.value == listing_.price, "Incorrect payment.");
        } else {
            require(allowedToken[listing_.paymentToken], "Payment token not allowed.");
            require(msg.value == 0, "Unexpected ETH.");
        }

        delete listing[nft_][tokenId_];

        _settle(nft_, tokenId_, listing_.seller, msg.sender, listing_.paymentToken, listing_.price);
    }

    /**
     * @notice Sends the caller's pending ETH to the caller.
     */
    function withdraw() external nonReentrant {
        _withdraw(msg.sender);
    }

    /**
     * @notice Sends the pending ETH of `account_` to `account_`.
     * @dev Callable by anyone, for accounts that cannot call {withdraw} themselves. Funds always go to
     * `account_`, never to the caller.
     * @param account_ Account whose pending ETH is paid out.
     */
    function withdrawFor(address account_) external nonReentrant {
        _withdraw(account_);
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

    function _withdraw(address account_) internal {
        uint256 amount_ = pendingEth[account_];
        require(amount_ > 0, "Nothing to withdraw.");

        pendingEth[account_] = 0;

        (bool success,) = account_.call{value: amount_}("");
        require(success, "Withdraw failed.");

        emit Withdrawn(account_, amount_);
    }

    function _getSellerListing(address nft_, uint256 tokenId_) internal view returns (Listing storage listing_) {
        listing_ = listing[nft_][tokenId_];
        require(listing_.seller != address(0), "Listing does not exist.");
        require(listing_.seller == msg.sender, "Not listing's seller.");
    }

    function _computeSplit(address nft_, uint256 tokenId_, uint256 price_)
        internal
        view
        returns (uint256 fee, address royaltyReceiver, uint256 royalty, uint256 proceeds)
    {
        fee = (price_ * feeBps) / BPS_DENOMINATOR;

        if (ERC165Checker.supportsInterface(nft_, type(IERC2981).interfaceId)) {
            (royaltyReceiver, royalty) = IERC2981(nft_).royaltyInfo(tokenId_, price_);
            if (royaltyReceiver == address(0)) royalty = 0;
        }
        require(royalty <= price_ - fee, "Fee plus royalty exceed price.");
        proceeds = price_ - fee - royalty;
    }

    function _settle(
        address nft_,
        uint256 tokenId_,
        address seller_,
        address buyer_,
        address paymentToken_,
        uint256 price_
    ) internal {
        (uint256 fee, address royaltyReceiver, uint256 royalty, uint256 proceeds) =
            _computeSplit(nft_, tokenId_, price_);

        if (paymentToken_ == address(0)) {
            _creditEth(seller_, proceeds, fee, royaltyReceiver, royalty);
        } else {
            _payToken(IERC20(paymentToken_), buyer_, seller_, proceeds, fee, royaltyReceiver, royalty);
        }

        IERC721(nft_).safeTransferFrom(seller_, buyer_, tokenId_);

        emit NFTSold(buyer_, seller_, nft_, tokenId_, paymentToken_, price_);
    }

    function _creditEth(address seller_, uint256 proceeds_, uint256 fee_, address royaltyReceiver_, uint256 royalty_)
        internal
    {
        pendingEth[seller_] += proceeds_;
        pendingEth[feeRecipient] += fee_;

        if (royalty_ > 0) pendingEth[royaltyReceiver_] += royalty_;
    }

    function _payToken(
        IERC20 token_,
        address buyer_,
        address seller_,
        uint256 proceeds_,
        uint256 fee_,
        address royaltyReceiver_,
        uint256 royalty_
    ) internal {
        if (proceeds_ > 0) token_.safeTransferFrom(buyer_, seller_, proceeds_);
        if (fee_ > 0) token_.safeTransferFrom(buyer_, feeRecipient, fee_);
        if (royalty_ > 0) token_.safeTransferFrom(buyer_, royaltyReceiver_, royalty_);
    }
}
