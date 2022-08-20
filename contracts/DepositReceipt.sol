pragma solidity =0.8.9;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

import "./Interfaces/IRouter.sol";
//dev debug
import "hardhat/console.sol";

contract DepositReceipt is  ERC721, AccessControl {
    
    // Role based access control, minters can mint or burn moUSD
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");  
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");  

    uint256 private NORMALIZE_DECIMALS = 1e12; //constant to bring 6dp USDC up to 18dp standard
    uint256 private BASE = 1 ether; //division base
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

    event AddNewMinter(address indexed account, address indexed addedBy);
    event NFTSplit(uint256 oldNFTId, uint256 newNFTId);
    event NFTDataModified(uint256 NFTId, uint256 pastPooledTokens, uint256 newPooledTokens);

    constructor(string memory _name, 
                string memory _symbol, 
                address _router, 
                address _token0,
                address _token1,
                bool _stable) 
                ERC721(_name, _symbol){

        //we dont want the `DEFAULT_ADMIN_ROLE` to exist as this doesn't require a 
        // time delay to add/remove any role and so is dangerous. 
        //So we ignore it and set our weaker admin role.
        _setupRole(ADMIN_ROLE, msg.sender);
        currentLastId = 1; //avoid id 0
        //set up details for underlying tokens
        router = IRouter(_router);
        token0 = _token0;
        token1 = _token1;
        stable = _stable;
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
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
    /**
   * @notice Splits a deposit Receipt  into two NFTs. Assigns `percentageSplit` of the original
   * pooled tokens to the new certificate.
   *
   * @param NFTId The id of the DepositReceipt NFT.
   * @param percentageSplit The percentage of pooled tokens assigned to the new NFT.
   */

   //Borrowed from original Lyra.finance ERC721 design.
  function split(uint256 NFTId, uint256 percentageSplit) external returns (uint) {
    require(percentageSplit < BASE, "split must be less than 100%");
    require(ownerOf(NFTId) == msg.sender, "only the owner can split their NFT");

    uint256 existingPooledTokens = pooledTokens[NFTId];
    uint256 newPooledTokens = (existingPooledTokens * percentageSplit)/ BASE;
    pooledTokens[NFTId] = existingPooledTokens - newPooledTokens;
    uint256 newNFTId = _mintNewNFT(newPooledTokens);
    

    emit NFTSplit(NFTId, newNFTId);
    emit NFTDataModified(NFTId, existingPooledTokens, existingPooledTokens - newPooledTokens);
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
        return (_mintNewNFT(_pooledTokenAmount));
    }

    /**
      * @notice Only callable by Minters via safeMint or  by split()
      * @dev Mints new NFT with '_pooledTokenAmount' of pooledTokens associated with it and emits Transfer event
      * @param _pooledTokenAmount amount of pooled tokens to be associated with NFT
     **/
    function _mintNewNFT( uint _pooledTokenAmount) internal returns(uint256){
        uint256 NFTId = currentLastId;
        currentLastId += 1;
        pooledTokens[NFTId] = _pooledTokenAmount;
        relatedDepositor[NFTId] = msg.sender; 
        _safeMint( msg.sender, NFTId);
        return(NFTId);

    }
    /**
     * @notice Pass through function that converts pooledTokens to underlying asset amounts. 
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
            value0 = token0Amount;
            //swap value takes into account slippage
            (value1, ) = router.getAmountOut(token1Amount,token1, token0 );
        }
        //token1 must be USDC 
        else {
            //hardcode value of USDC at $1
            value1 = token1Amount;
            //swap value takes into account slippage
            (value0, ) = router.getAmountOut(token0Amount,token0, token1 );
        }
        //Invariant: both value0 and value1 are in USDC scale 6.d.p now
        //USDC has only 6 decimals so we bring it up to the same scale as other 18d.p ERC20s
        return((value0 + value1)*NORMALIZE_DECIMALS);
    }
}