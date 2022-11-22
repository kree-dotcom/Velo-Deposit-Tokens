# DepositReceipt.sol Purpose and functions

DepositReceipt is an ERC721 designed to be used as collateral for loans, specifically in isomorph.loans .

DepositReceipts contain two roles, ADMIN and MINTER. the former is a role reserved for the Templater.sol contract. It uses it's admin role to add MINTERs, it has no other functionality and cannot remove MINTERs.

The MINTER role is reserved for instances of Depositor.sol. Only Addresses with the MINTER role are able to destroy DepositReceipt NFTs. Only MINTERs and calls to `split()` can create new DepositReceipt NFTs

## Functions

### constructor
Instances of DepositReceipt are created when a new Templater is created, the Templater passes in the characteristics of the pooled token that this DepositReceipt relates to as well as connecting some of the interfaces to their required endpoints. The Velodrome router is set up so we can later pass through liquidity removal queries and the Chainlink price oracle is passed through to cement where we query for the non-USDC token's value from. In this set up we set up some sanity boundaries for the Chainlink oracle to prevent stale prices being used or prevent the value being incorrectly reported if the oracle reachs one of it's boundaries as happened with LUNA. 


### priceLiquidity
This view function allows users and contracts to determine the dollar value of a certain quantity of pooledTokens. It makes use of the viewQuoteRemoveLiquidity and getOraclePrice functions to determine the value of both tokens in the pair. As one token is USDC we branch the behaviour depending which token is USDC, then fetch the oracle price for the other token. The returned dollar value is in Ether scale, i.e. 1*10^18 = $1.00. To prevent flash swaps from changing the underlying pool token composure we check the exchange rate for 100 of the token we have paired USDC with. Then using the Chainlink price we create an upper and lower bound for this exchange rate and revert if the swap rate is not in the range (lower bound, upper bound).

 The reason for checking a swap of 100 tokens is because this makes it slightly more expensive to DOS the priceOracle. This DOS is possible as we check the pool we have performed the swap price check by is the same pool we are using the deposit receipt for by looking at if it is stable or volatile. Therefore a malicious user could possibly force the pool to price through the wrong pool and this would cause calls to `priceLiquidity()` to revert as long as they can sustain a price difference in the pool of choice. Requiring a price check on 100 tokens means the pool we check against must have some liquidity greater than $10 and therefore other users should arb any attempt to sustain an inaccurate price. In price the `HUNDRED_TOKENS` can be swapped out to ensure the value of the swap remain around $100 or larger.



 
