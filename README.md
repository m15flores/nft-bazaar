# NFTBazaar

A fixed-price NFT marketplace I built to practice the backend side of on-chain payments: who gets paid, in what order, and what happens when one of the parties misbehaves. Solidity 0.8.34, Foundry, OpenZeppelin 5.x.

It started as one of the exercises of the Blockchain Accelerator and I extended it well past the exercise: ERC20 payments, ERC-2981 royalties, pull payments, attack tests and a real deployment. **It is not audited and only lives on a testnet.**

- Network: Arbitrum Sepolia (421614)
- `NFTBazaar`: [`0x65ae34AF5ec21da37450655e1bC5067582D3e8c9`](https://sepolia.arbiscan.io/address/0x65ae34af5ec21da37450655e1bc5067582d3e8c9#code) (verified)
- Demo collection: [`0x7A0c585092FFcA8EDCE81Dd81117636AFB951a03`](https://sepolia.arbiscan.io/address/0x7a0c585092ffca8edce81dd81117636afb951a03#code) (verified). It is a mock with an open `mint`, only for the demo.

## What it does

A seller lists an NFT (it stays in their wallet, the marketplace only needs an approval) in ETH or in an allowlisted ERC20. A buyer pays the listed price. The price is split in three: a platform fee (basis points, capped at 10 %), the ERC-2981 royalty if the collection has one, and the rest for the seller.

```
       seller                                    bazaar                                     buyer
          |                                         |                                         |
          |-- approve(bazaar, tokenId) ------------>|                                         |
          |-- listNFT(nft, id, token, price, end) ->| stores the Listing                      |
          |                                         | (the NFT stays in the seller's wallet)  |
          |                                         |<-- buyNFT(nft, id, maxPrice) -----------|
          |                                         | checks, then delete listing             |
          |                                         | _settle:                                |
          |                                         |  1. _computeSplit                       |
          |                                         |  2. ETH: credit pendingEth              |
          |                                         |     ERC20: buyer pays the 3 recipients  |
          |                                         |  3. emit NFTSold                        |
          |                                         |  4. safeTransferFrom (last)             |
          |                                         |                                         |
          |-- withdraw() -------------------------->| pays out pendingEth                     |
```

ETH goes through a `pendingEth` balance that each party pulls with `withdraw()`. ERC20 goes straight from the buyer to the three recipients, so the contract never holds tokens.

I left out the Dutch auction and WETH offers I had planned. The `startTime` and `endPrice` fields in `Listing` are left over from that and are not used.

## Decisions worth explaining

**Pull payments for ETH.** If I push ETH to the seller and the seller is a contract that reverts, nobody can ever buy that NFT. With pull payments a bad receiver only blocks its own withdrawal.

**No custody for ERC20.** I first thought about holding the tokens and adding a token withdraw, but that means more code and, with USDC-style blacklists, a blocked contract address would freeze everything. Paying directly avoids both.

**Order inside `buyNFT`.** The listing is deleted before anything else, and the NFT transfer is the last call, because `safeTransferFrom` runs `onERC721Received` on the buyer. `emit NFTSold` goes before it so the logs stay in order if the buyer re-enters.

**`maxPrice_`.** With ETH the buyer sends the exact price, so there is nothing to protect. With ERC20 people usually approve a lot, so a seller could change the price (or cancel and relist) right before the purchase and the buyer would pay something they never saw. Blocking `updatePrice` does not solve it because of cancel and relist, so the buyer passes the maximum they accept.

**`call` in `withdraw`.** `transfer` only forwards 2300 gas and breaks contract wallets. Reentrancy is covered by `nonReentrant` and by zeroing the balance before the call. Either one alone is enough, I kept both on purpose (more on this in Testing).

**Stale listings.** If a seller moves the NFT after listing it, the listing stays but the purchase reverts, since the approval is gone. The new owner can list over it.

## Threats I tested

| What | How it is handled | Test |
|---|---|---|
| Buyer re-enters `buyNFT` from `onERC721Received` | `nonReentrant` + state written first | `test_Attack_RevertWhen_BuyerReentersBuyNFT` |
| Receiver re-enters `withdraw` | `nonReentrant` + balance zeroed before the call | `test_Attack_RevertWhen_ReceiverReentersWithdraw` |
| Receiver that rejects ETH | Only its own withdraw reverts | `test_Withdraw_RevertWhen_ReceiverRejectsEth` |
| Royalty receiver blacklisted in the token | Sale reverts, nothing is lost | `test_Attack_RevertWhen_RoyaltyReceiverIsBlacklisted` |
| Fee recipient blacklisted | Owner calls `setFeeRecipient` and sales resume | `test_Attack_PurchaseSucceeds_AfterOwnerReplacesBlacklistedFeeRecipient` |
| Price raised before an ERC20 purchase | `maxPrice_` | `test_BuyNFT_RevertWhen_PriceRaisedAboveMaxPrice` |
| Listing left behind after the NFT moved | Purchase reverts, new owner can relist | `test_BuyNFT_RevertWhen_ListingIsStale`, `test_Attack_NewOwnerOverwritesStaleListing` |

## Known limitations

- Not audited, and I did not run Slither.
- The owner is a trust point (fee up to 10 %, fee recipient, token allowlist). On mainnet it should be a multisig.
- A blacklisted royalty receiver blocks sales of that collection in that token. The seller can relist in ETH. I thought about paying that part to the seller when the transfer fails and decided it was not worth the extra code for a rare case.
- Fee-on-transfer and rebasing tokens would leave the seller with less. The allowlist is the only defence.
- `renounceOwnership` is inherited and would freeze the fee and the allowlist.
- An NFT whose `royaltyInfo` reverts cannot be bought.
- A buyer can buy their own listing; it only costs them the fee.

## Tests

140 tests in 6 suites (`forge test`).

| Suite | Tests | Covers |
|---|---|---|
| `NFTBazaar.t.sol` | 65 | constructor, admin, `listNFT`, `cancelListing`, `updatePrice` |
| `NFTBazaar.Split.t.sol` | 14 | fee and royalty maths, rounding, overflow |
| `NFTBazaar.Settle.t.sol` | 24 | `_settle` in ETH and ERC20 |
| `NFTBazaar.Buy.t.sol` | 24 | `buyNFT`, time boundaries, `maxPrice_` |
| `NFTBazaar.Withdraw.t.sol` | 8 | `withdraw` |
| `NFTBazaar.Attacks.t.sol` | 5 | reentrancy, blacklist, relisting |

Coverage, from `forge coverage --no-match-coverage "(test|script)"`:

| File | Lines | Statements | Branches | Functions |
|---|---|---|---|---|
| `src/NFTBazaar.sol` | 100% (84/84) | 100% (76/76) | 100% (52/52) | 100% (16/16) |

Internal functions (`_computeSplit`, `_settle`) are tested through a small harness contract. Fuzz tests use `bound`, never `vm.assume`, and check that fee + royalty + proceeds equals the price to the wei.

Coverage only says a line ran, so after each block I mutated the code by hand (removed lines, flipped `+=` to `=`, moved statements) and checked that some test failed. Two findings I found interesting:

- Removing `nonReentrant` from `withdraw`, or moving `= 0` after the `call`, does not fail any test on its own, because each defence covers the other. Only removing both makes the attack test fail.
- Removing `require(amount_ > 0)` in `withdraw` fails two tests, so it is not redundant.

## Deployment and demo

Deployed with `script/Deploy.s.sol` (fee 2.5 %, 5 % royalty to a separate creator account). Then one sale of 0.001 ETH between three accounts:

| Step | Account | Tx |
|---|---|---|
| Deploy `NFTBazaar` | deployer | [`0x9295a21b...94545`](https://sepolia.arbiscan.io/tx/0x9295a21ba357c1340ec0dc19beb3f13b2c8836f7c602cc864736bc45e4994545) |
| Deploy collection | deployer | [`0x4dbb6257...d012d`](https://sepolia.arbiscan.io/tx/0x4dbb6257cc936391fc9daa80ff71cd343cf5d4c75b45a6bd448a54da89cd012d) |
| `setDefaultRoyalty` (5 %) | deployer | [`0x6652a83b...51d02`](https://sepolia.arbiscan.io/tx/0x6652a83b2d3b078316ebd9f7cba46bf98df1425bb60ef54bec65af9447a51d02) |
| `mint(seller, 1)` | deployer | [`0xe88fc3d4...ed0f4`](https://sepolia.arbiscan.io/tx/0xe88fc3d49d16006693451a9e115112807b18c1e36a1cf242815b6bb1ba9ed0f4) |
| `approve` | seller | [`0xe0898cb3...7202c`](https://sepolia.arbiscan.io/tx/0xe0898cb3e3e941a5a09bd878e393019b5ad0bf0534ca9846cf437b090f07202c) |
| `listNFT` | seller | [`0x46040890...78a34`](https://sepolia.arbiscan.io/tx/0x4604089abe09cbaecf09722f80515c012cf7fbf0da6639c408f886b6ece78a34) |
| `buyNFT` | buyer | [`0x031251d7...57f6c`](https://sepolia.arbiscan.io/tx/0x031251d7b912b1382ebb79b418f3e4389aa2df2717d19638bb8af5c999257f6c) |
| `withdraw` | seller | [`0xa193ab72...615d9`](https://sepolia.arbiscan.io/tx/0xa193ab726ea6c2deca705441401654db7cc1a15f7a706ace7ef77a63b20615d9) |
| `withdraw` | fee recipient | [`0x60e492a4...74206`](https://sepolia.arbiscan.io/tx/0x60e492a474652874fa89616779c421689e49d03fd2207b4cd50998d2fce74206) |

The split read from `pendingEth` right after the sale: seller 0.000925 ETH, fee recipient 0.000025 ETH, royalty creator 0.00005 ETH. They add up to the price. The creator never withdrew because that account has no gas.

## Layout

```
src/NFTBazaar.sol          contract
script/Deploy.s.sol        deployment script
test/                      6 suites
test/harness/              harness for internal functions
test/mocks/                mocks and attackers
```