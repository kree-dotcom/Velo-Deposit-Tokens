pragma solidity =0.8.9;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

//chainlink aggregator interface extended 
import "./Interfaces/IAggregatorV3.sol";
import "./Interfaces/IAccessControlledOffchainAggregator.sol";

import "./Interfaces/IRouter.sol";
import "./Interfaces/IPair.sol";


abstract contract DepositReceipt_Base is  ERC721Enumerable, AccessControl {
    
    // Role based access control, minters can mint or burn moUSD
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");  
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");  

    
    uint256 private immutable heartbeat_time_token0; //Check heartbeat frequency when adding new feeds
    uint256 private immutable heartbeat_time_token1;
    uint256 constant BASE = 1 ether; //division base
    
    //Mapping from NFTid to number of associated poolTokens
    mapping(uint256 => uint256) public pooledTokens;
    //Mapping from NFTid to original depositor contract(where tokens can be redeemed by anyone)
    mapping(uint256 => address) public relatedDepositor;

    //last NFT id, used as key
    uint256 public currentLastId;

    //router used for underlying asset quotes
    IRouter public router;

    //underlying gauge token details
    address public token0; 
    address public token1;
    bool public stable; //which pool to route trades through, stable or volatile
    IPair public pair; //address of the related pool

    
    
    

    event AddNewMinter(address indexed account, address indexed addedBy);
    event NFTSplit(uint256 oldNFTId, uint256 newNFTId);
    event NFTDataModified(uint256 NFTId, uint256 pastPooledTokens, uint256 newPooledTokens);


    modifier onlyMinter{
        require(hasRole(MINTER_ROLE, msg.sender), "Caller is not a minter");
        _;
    }

    modifier onlyAdmin{
        require(hasRole(ADMIN_ROLE, msg.sender), "Caller is not an admin");
        _;
    }

    constructor(uint256 _heartbeat_token0, uint256 _heartbeat_token1){
        heartbeat_time_token0 = _heartbeat_token0;
        heartbeat_time_token1 = _heartbeat_token1;
    }
    
    function addMinter(address _account) external onlyAdmin{
        _setupRole(MINTER_ROLE, _account);
        emit AddNewMinter(_account,  msg.sender);
    }

    /**
   * @notice as supportsInterface is present in both ERC721 and AccessControl we must specify the override here to dictate the order
   */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721Enumerable, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
    /**
   * @notice Splits a deposit Receipt  into two NFTs. Assigns `percentageSplit` of the original
   * pooled tokens to the new certificate.
   * @notice only the owner of an NFTId or approved approved addresses can split an NFT
   * @param _NFTId The id of the DepositReceipt NFT.
   * @param _percentageSplit The percentage of pooled tokens assigned to the new NFT.
   */

   //Borrowed from original Lyra.finance ERC721 design.
  function split(uint256 _NFTId, uint256 _percentageSplit) external returns (uint256) {
    require(_percentageSplit < BASE, "split must be less than 100%");
    require(_isApprovedOrOwner(msg.sender, _NFTId), "ERC721: caller is not token owner or approved");

    uint256 existingPooledTokens = pooledTokens[_NFTId];
    uint256 newPooledTokens = (existingPooledTokens * _percentageSplit)/ BASE;
    pooledTokens[_NFTId] = existingPooledTokens - newPooledTokens;
    uint256 newNFTId = _mintNewNFT(newPooledTokens, relatedDepositor[_NFTId]);
    

    emit NFTSplit(_NFTId, newNFTId);
    emit NFTDataModified(_NFTId, existingPooledTokens, existingPooledTokens - newPooledTokens);
    emit NFTDataModified(newNFTId, 0, newPooledTokens);
    return newNFTId;
    }
    
     /**
      * @notice Only minter roles can burn Deposit receipts
      * @dev burns 'amount' of tokens to address 'account', and emits Transfer event to 
      * to zero address.
      * @param _NFTId The NFT id of the token to be burned, sender must be holder or approved by holder
     **/
    function burn(uint256 _NFTId) external onlyMinter{
        require(_isApprovedOrOwner(msg.sender, _NFTId), "ERC721: caller is not token owner or approved");
        delete pooledTokens[_NFTId];
        delete relatedDepositor[_NFTId];
        _burn(_NFTId);
    }
    /**
      * @notice Only minter roles can mint Deposit receipts for new Pooled Tokens
      * @dev Mints new NFT with '_pooledTokenAmount' of pooledTokens associated with it
      * @param _pooledTokenAmount amount of pooled tokens to be associated with NFT
     **/
    function safeMint( uint _pooledTokenAmount) external onlyMinter returns(uint256){
        return (_mintNewNFT(_pooledTokenAmount, msg.sender));
    }

    /**
      * @notice Only callable by Minters via safeMint or  by split()
      * @dev Mints new NFT with '_pooledTokenAmount' of pooledTokens associated with it and emits Transfer event
      * @param _pooledTokenAmount amount of pooled tokens to be associated with NFT
      * @param _depositor the address to be recorded as the related depositor where the pooledTokens can be withdrawn from
     **/
    function _mintNewNFT( uint _pooledTokenAmount, address _depositor) internal returns(uint256){
        uint256 NFTId = currentLastId;
        currentLastId += 1;
        pooledTokens[NFTId] = _pooledTokenAmount;
        relatedDepositor[NFTId] = _depositor; 
        _safeMint( msg.sender, NFTId);
        return(NFTId);

    }
    /**
     * @notice Pass through function that converts pooledTokens to underlying asset amounts. 
     * @dev for pricing THIS MUST NOT be used in isolation, use priceLiquidity instead
     * @param _liquidity amount of pooledTokens you want to find the underlying liquidity for.
     */
    function viewQuoteRemoveLiquidity(uint256 _liquidity) public view returns( uint256, uint256 ){
        uint256 token0Amount;
        uint256 token1Amount;
        (token0Amount, token1Amount) = router.quoteRemoveLiquidity(
                                    token0, 
                                    token1,
                                    stable,
                                    _liquidity );
        return (token0Amount, token1Amount);

    }

    /** 
     * @dev This function is view but uses block.timestamp which will only return a non-zero value in a tx call.
     * @param _priceFeed the Chainlink aggregator for the price you want to retrieve, ETH or Token.
     * @return Oracle price converted to a uint256 for ease of use elsewhere
     */
    function getOraclePrice(IAggregatorV3 _priceFeed, address token) public view returns (uint256 ) {
        (
            uint80 roundID,
            int signedPrice,
            /*uint startedAt*/,
            uint timeStamp,
            uint80 answeredInRound
        ) = _priceFeed.latestRoundData();
        //check for Chainlink oracle deviancies, force a revert if any are present. Helps prevent a LUNA like issue
        require(signedPrice > 0, "Negative Oracle Price");
        uint256 heartbeat_time;
        if (token == token0){
            heartbeat_time = heartbeat_time_token0;
        }
        else{
            heartbeat_time = heartbeat_time_token1;
        }
        require(timeStamp >= block.timestamp - heartbeat_time , "Stale pricefeed");
        IAccessControlledOffchainAggregator  aggregator = IAccessControlledOffchainAggregator(_priceFeed.aggregator());
        //fetch the pricefeeds hard limits so we can be aware if these have been reached.
        int192 tokenMinPrice = aggregator.minAnswer();
        int192 tokenMaxPrice = aggregator.maxAnswer();
        //The min/maxPrice is the smallest/largest value the aggregator will post and so if it is reached we can no longer trust the oracle price hasn't gone beyond it.
        require(signedPrice < tokenMaxPrice, "Upper price bound breached"); 
        require(signedPrice > tokenMinPrice, "Lower price bound breached");
        require(answeredInRound >= roundID, "round not complete");
        uint256 price = uint256(signedPrice);
        return price;


    }

   /**
    *  @notice this is used to price pooled Tokens by determining their underlying assets and then pricing these
    *  @notice the two ways to do this are to price to USDC as  a dollar equivalent or to ETH then use Chainlink price feeds
    *  @dev each DepositReceipt has a bespoke valuation method, make sure it fits the tokens
    *  @dev each DepositReceipt's valuation method is sensitive to available liquidity keep this in mind as liquidating a pooled token by using the same pool will reduce overall liquidity

    */
    function priceLiquidity(uint256 _liquidity) external virtual view returns(uint256);
}