pragma solidity =0.8.9;

import "./DepositReceipt.sol";
import "./Depositor.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";


//Templater clones the deposit contract and attachs it to the deposit token as 
//another trusted minter.
contract Templater {

    DepositReceipt depositReceipt;
    mapping(address => address) public UserToDepositor;
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    //store token info to know which pooled pair this Templater relates to.
    address public token0;
    address public token1;
    bool public stablePool;
    address AMMToken;
    address gauge;

    event newDepositorMade(address User, address Depositor);
    event DepositReceiptSetUp(address DepositReceipt);

    constructor(address _token0, address _token1, bool _stable, address _AMMToken, address _gauge){
        string memory name;
        string memory symbol;
        AMMToken = _AMMToken;
        gauge = _gauge;
        if (_stable) {
            name = string(abi.encodePacked("Deposit-Receipt-StableV1 AMM - ", IERC20Metadata(_token0).symbol(), "/", IERC20Metadata(_token1).symbol()));
            symbol = string(abi.encodePacked("Receipt-sAMM-", IERC20Metadata(_token0).symbol(), "/", IERC20Metadata(_token1).symbol()));
        } else {
            name = string(abi.encodePacked("VDeposit-Receipt-VolatileV1 AMM - ", IERC20Metadata(_token0).symbol(), "/", IERC20Metadata(_token1).symbol()));
            symbol = string(abi.encodePacked("Receipt-vAMM-", IERC20Metadata(_token0).symbol(), "/", IERC20Metadata(_token1).symbol()));
        }
        depositReceipt = new DepositReceipt(name, symbol);
        emit DepositReceiptSetUp(address(depositReceipt));
    }

    function makeNewDepositor()  external returns(address newDepositor) {
        require(UserToDepositor[msg.sender] == address(0), "User already has Depositor");
        Depositor depositor = new Depositor(address(depositReceipt), AMMToken, gauge);
        depositReceipt.addMinter(address(depositor));  
        UserToDepositor[msg.sender] = address(depositor); 
        emit newDepositorMade(msg.sender, address(depositor));   
        return address(depositor);
    }
    
}