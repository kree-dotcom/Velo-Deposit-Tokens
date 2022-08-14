pragma solidity =0.8.9;

import "./DepositReceipt.sol";
import "./Interfaces/IGauge.sol";
import "./Interfaces/IRouter.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


//Depositer takes pooled tokens from the user and deposits them on their behalf 
// into the Gauge. It then mints them the  ERC20 deposit receipt to use elsewhere
// the initial Depositer can claim rewards from the Guage via the Depositer at any time
contract Depositor is Ownable {

    using SafeERC20 for IERC20; 

    DepositReceipt public depositReceipt;
    IERC20 public AMMToken;
    IGauge public gauge;
    IRouter public router;
    address public token0; 
    address public token1;
    bool public stable;

    constructor(
                address _depositReceipt,
                address _AMMToken, 
                address _gauge,
                address _router,
                address _token0,
                address _token1,
                bool _stable
                ){

        AMMToken = IERC20(_AMMToken);
        gauge = IGauge(_gauge);
        depositReceipt = DepositReceipt(_depositReceipt);
        router = IRouter(_router);
        token0 = _token0;
        token1 = _token1;
        stable = _stable;
    }

    function onERC721Received(
        address operator,
        address from,
        uint tokenId,
        bytes calldata data
    ) external returns (bytes4){
        return(IERC721Receiver.onERC721Received.selector);
    }

    function viewQuoteRemoveLiquidity(uint256 _liquidity) external view returns( uint256, uint256 ){
        uint256 token0Amount;
        uint256 token1Amount;
        (token0Amount, token1Amount) = router.quoteRemoveLiquidity(
                                    token0, 
                                    token1,
                                    stable,
                                    _liquidity );
        return (token0Amount, token1Amount);

    }

    function depositToGauge(uint256 _amount) onlyOwner() external returns(uint256){
        bool success = AMMToken.transferFrom(msg.sender, address(this), _amount);
        require(success, "TransferFrom failed");
        AMMToken.safeIncreaseAllowance(address(gauge), _amount);
        gauge.deposit(_amount);
        uint256 NFTId = depositReceipt.safeMint(_amount);
        depositReceipt.safeTransferFrom(address(this), msg.sender, NFTId);
        return(NFTId);
    }
    /*
    * @notice used to withdraw percentageSplit of specified NFT worth of pooledTokens.
    */
    function partialWithdrawFromGauge(uint256 _NFTId, uint256 percentageSplit, address[] memory _tokens) external {
        uint256 newNFTId = depositReceipt.split(_NFTId, percentageSplit);
        //then call withdrawFromGauge on portion removing.
        withdrawFromGauge(newNFTId, _tokens);
    }   

    /*
    * @notice burns the NFT related to the ID and withdraws the owed pooledtokens from Gauge and sends to user.  
    */
    function withdrawFromGauge(uint256 _NFTId, address[] memory _tokens)  public  {
        uint256 amount = depositReceipt.pooledTokens(_NFTId);
        depositReceipt.burn(_NFTId);
        gauge.getReward(address(this), _tokens);
        gauge.withdraw(amount);
        AMMToken.transfer(msg.sender, amount);
    }

    //think about manipulation with fake reward tokens, shouldn't be an issue due to onlyOwner but verify.
    //think about reverts here, i.e. if we call getReward when can it revert?
    //what happens if one reward token isn't transferable, can we skip it?
    function claimRewards( address[] memory _tokens) onlyOwner() public {
        require(_tokens.length > 0, "Empty tokens array");
        gauge.getReward(address(this), _tokens);
        //some logic here to withdraw each of the tokens?
        uint256 length =  _tokens.length;
        for (uint i = 0; i < length; i++) {
            uint256 balance = IERC20(_tokens[i]).balanceOf(address(this));
            IERC20(_tokens[i]).transfer(msg.sender, balance);
        }

    }

    function viewPendingRewards(address _token) external view returns(uint256){
        //passthrough to Gauge
        return gauge.earned(_token, address(this)); 
    }
    
}