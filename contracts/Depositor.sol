pragma solidity =0.8.9;

import "./DepositReceipt.sol";
import "./Interfaces/IGauge.sol";
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

    constructor(address _depositReceipt, address _AMMToken, address _gauge){
        AMMToken = IERC20(_AMMToken);
        gauge = IGauge(_gauge);
        depositReceipt = DepositReceipt(_depositReceipt);
    }

    function depositToGauge(uint256 _amount) onlyOwner() external {
        bool success = AMMToken.transferFrom(msg.sender, address(this), _amount);
        require(success, "TransferFrom failed");
        AMMToken.safeIncreaseAllowance(address(gauge), _amount);
        gauge.deposit(_amount);
        depositReceipt.mint(_amount);
        depositReceipt.transfer(msg.sender, _amount);
    }

    function withdrawFromGauge(uint256 _amount, address[] memory _tokens) onlyOwner() external {
        depositReceipt.burn(msg.sender, _amount);
        claimRewards(_tokens); //wise to claim rewards before withdrawing?
        gauge.withdraw(_amount);
        AMMToken.transfer(msg.sender, _amount);
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
        return gauge.earned(_token, address(this)); //ARE WE SURE THIS IS THE RIGHT FUNCTION?
    }
    
}