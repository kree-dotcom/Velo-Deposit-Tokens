# DepositReceipt.sol Purpose and functions

DepositReceipt is an ERC721 designed to be used as collateral for loans, specifically in isomorph.loans .

DepositReceipts contain two roles, ADMIN and MINTER. the former is a role reserved for the Templater.sol contract. It uses it's admin role to add MINTERs, it has no other functionality and cannot remove MINTERs.

The MINTER role is reserved for instances of Depositor.sol. Only Addresses with the MINTER role are able to destroy DepositReceipt NFTs. Only MINTERs and calls to `split()` can create new DepositReceipt NFTs

## Functions

### constructor
Instances of DepositReceipt are created when a new Templater is created, the Templater passes in the characteristics of the pooled token that this DepositReceipt relates to as well as connecting some of the interfaces to their required endpoints. The Velodrome router is set up so we can later pass through liquidity removal queries and the Chainlink price oracle is passed through to cement where we query for the non-USDC token's value from. In this set up we set up some sanity boundaries for the Chainlink oracle to prevent stale prices being used or prevent the value being incorrectly reported if the oracle reachs one of it's boundaries as happened with LUNA. 

### addMinter
This ADMIN only function is called by the Templater every time a new instance of Depositor is created by the Templater. This function should ONLY be callable by the Templater that created this DepositReceipt. The new Depositor address is added to the list of MINTERs who can mint or burn the related DepositReceipt NFTs.

### supportsInterface
An override function to specify that we wish supportsInterface calls to return the ERC721Enumerable supportsInterface function NOT the AccessControl supportsInterface function.

### split 
The split function is used to take an existing DepositReceipt NFT and split it into two DepositReceipt NFTs. In doing so it will allocate _percentageSplit of the pooledTokens to the new NFT. Any remaining pooledTokens are then left at the older NFT. Only the NFT owner or an address approved by the owner can split an NFT. 

### burn 
Only MINTER role addresses can burn an NFT. An NFT should only ever be burned if the user is requesting back the underlying pooledTokens from the Depositor contract. Once the user has the related pooledTokens back the DepositReceipt NFT has no meaning and so we destroy it, deleting previously related mappings. 

### safeMint 
Only MINTER role addresses can mint an NFT via this function. It acts as a passthrough for internal function _mintNewNFT

### _mintNewNFT
This internal function is the only way to make new DepositReceipt NFTs. It increments the ID before creating a new NFT and records the number of pooledTokens related to the new NFT. We record the depositor as given by the second arg, this should either be msg.sender if called directly by a Depositor or if called via `split()` we pass in the existing NFT's Depositor address.

### viewQuoteRemoveLiquidity
This view function passes requests through to the underlying Velodrome router which returns the amount of each token that would be received if the given pooledToken liquidity was removed.

### getOraclePrice
This view function wraps around the Chainlink USD oracle, using the boundaries set in the constructor to validate the returned price is safe to use along with other sanity checks. We can safely cast the Chainlink signed int price to unsigned as we have checked it is greater than zero. 

### priceLiquidity
This view function allows users and contracts to determine the dollar value of a certain quantity of pooledTokens. It makes use of the viewQuoteRemoveLiquidity and getOraclePrice functions to determine the value of both tokens in the pair. As one token is USDC we branch the behaviour depending which token is USDC, then fetch the oracle price for the other token. The returned dollar value is in Ether scale, i.e. 1*10^18 = $1.00



 
