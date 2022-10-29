pragma solidity =0.8.9;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

//chainlink aggregator interface extended 
import "./Interfaces/IAggregatorV3.sol";
import "./Interfaces/IAccessControlledOffchainAggregator.sol";

import "./Interfaces/IRouter.sol";
//dev debug
import "hardhat/console.sol";

contract DepositReceipt is  ERC721Enumerable, AccessControl {
    
    // Role based access control, minters can mint or burn moUSD
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");  
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");  

    uint256 private immutable oracleBase;
    uint256 private constant HEARTBEAT_TIME = 24 hours; //Check heartbeat frequency when adding new feeds
    uint256 private constant BASE = 1 ether; //division base
    uint256 private constant SCALE_SHIFT = 1e12; //brings USDC 6.d.p up to 18d.p. standard
    //Mapping from NFTid to number of associated poolTokens
    mapping(uint256 => uint256) public pooledTokens;
    //Mapping from NFTid to original depositor contract(where tokens can be redeemed by anyone)
    mapping(uint256 => address) public relatedDepositor;

    //last NFT id, used as key
    uint256 currentLastId;

    address private constant USDC = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607; 
    //underlying gauge token details
    address public immutable token0; 
    address public immutable token1;
    bool public immutable stable;

    
    //router used for underlying asset quotes
    IRouter public immutable router;
    //Chainlink oracle source
    IAggregatorV3 priceFeed;
    //hardcoded price bounds used by chainlink
    int192 immutable maxPrice;
    int192 immutable minPrice;

    event AddNewMinter(address indexed account, address indexed addedBy);
    event NFTSplit(uint256 oldNFTId, uint256 newNFTId);
    event NFTDataModified(uint256 NFTId, uint256 pastPooledTokens, uint256 newPooledTokens);

    /**
    *    @notice Zero address checks done in Templater that generates DepositReceipt and so not needed here.
    **/
    constructor(string memory _name, 
                string memory _symbol, 
                address _router, 
                address _token0,
                address _token1,
                bool _stable,
                address _priceFeed) 
                ERC721(_name, _symbol){

        //we dont want the `DEFAULT_ADMIN_ROLE` to exist as this doesn't require a 
        // time delay to add/remove any role and so is dangerous. 
        //So we ignore it and set our weaker admin role.
        _setupRole(ADMIN_ROLE, msg.sender);
        currentLastId = 1; //avoid id 0
        //set up details for underlying tokens
        router = IRouter(_router);

        //here we check one token is USDC and that the other token has 18d.p.
        //this prevents pricing mistakes and is defensive design against dev oversight.
        //Obvious this is not a full check, a malicious ERC20 can set it's own symbol as USDC too 
        //but in practice as only the multi-sig should be deploying via Templater this is not a concern 
        
        bytes memory USDCSymbol = abi.encodePacked("USDC");
        bytes memory token0Symbol = abi.encodePacked(IERC20Metadata(_token0).symbol());
        //equality cannot be checked for strings so we hash them first.
        if (keccak256(token0Symbol) == keccak256(USDCSymbol)){
            require( IERC20Metadata(_token1).decimals() == 18, "Token does not have 18dp");
        }
        else
        {   
            bytes memory token1Symbol = abi.encodePacked(IERC20Metadata(_token1).symbol());
            
            require( keccak256(token1Symbol) == keccak256(USDCSymbol), "One token must be USDC");
            require( IERC20Metadata(_token0).decimals() == 18, "Token does not have 18dp");
            
        }

        token0 = _token0;
        token1 = _token1;
        stable = _stable;
        priceFeed = IAggregatorV3(_priceFeed);
        IAccessControlledOffchainAggregator  aggregator = IAccessControlledOffchainAggregator(priceFeed.aggregator());
        //fetch the pricefeeds hard limits so we can be aware if these have been reached.
        minPrice = aggregator.minAnswer();
        maxPrice = aggregator.maxAnswer();
        oracleBase = 10 ** priceFeed.decimals();  //Chainlink USD oracles have 8d.p.
    }

    modifier onlyMinter{
        require(hasRole(MINTER_ROLE, msg.sender), "Caller is not a minter");
        _;
    }

    modifier onlyAdmin{
        require(hasRole(ADMIN_ROLE, msg.sender), "Caller is not an admin");
        _;
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
     * @return Oracle price converted to a uint256 for ease of use elsewhere
     */
    function getOraclePrice() public view returns (uint256 ) {
        (
            /*uint80 roundID*/,
            int signedPrice,
            /*uint startedAt*/,
            uint timeStamp,
            /*uint80 answeredInRound*/
        ) = priceFeed.latestRoundData();
        //check for Chainlink oracle deviancies, force a revert if any are present. Helps prevent a LUNA like issue
        require(signedPrice > 0, "Negative Oracle Price");
        require(timeStamp >= block.timestamp - HEARTBEAT_TIME , "Stale pricefeed");
        require(signedPrice < maxPrice, "Upper price bound breached");
        require(signedPrice > minPrice, "Lower price bound breached");
        uint256 price = uint256(signedPrice);
        return price;


    }

   /**
    *  @notice this is used to price pooled Tokens by determining their underlying assets and then pricing these
    *  @notice the two ways to do this are to price to USDC as  a dollar equivalent or to ETH then use Chainlink price feeds
    *  @dev each DepositReceipt has a bespoke valuation method, make sure it fits the tokens
    *  @dev each DepositReceipt's valuation method is sensitive to available liquidity keep this in mind as liquidating a pooled token by using the same pool will reduce overall liquidity

    */
    function priceLiquidity(uint256 _liquidity) external view returns(uint256){
        uint256 token0Amount;
        uint256 token1Amount;
        (token0Amount, token1Amount) = viewQuoteRemoveLiquidity(_liquidity);
        //USDC route 
        uint256 value0;
        uint256 value1;
        if (token0 == USDC){
            //hardcode value of USDC at $1
            value0 = token0Amount * SCALE_SHIFT;
            
            value1 = (token1Amount * getOraclePrice()) / oracleBase;
        }
        //token1 must be USDC 
        else {
            //hardcode value of USDC at $1
            value1 = token1Amount * SCALE_SHIFT;
           
            value0 = (token0Amount * getOraclePrice()) / oracleBase;
        }
        //Invariant: both value0 and value1 are in ETH scale 6.d.p now
        //USDC has only 6 decimals so we bring it up to the same scale as other 18d.p ERC20s
        return(value0 + value1);
    }
}