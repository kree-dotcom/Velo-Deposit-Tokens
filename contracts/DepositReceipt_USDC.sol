pragma solidity =0.8.9;

import "./DepositReceipt_Base.sol";
import "hardhat/console.sol";

contract DepositReceipt_USDC is  DepositReceipt_Base {

    uint256 private constant SCALE_SHIFT = 1e12; //brings USDC 6.d.p up to 18d.p. standard
    uint256 private constant USDC_BASE = 1e6; //used for division in USDC 6.d.p scale
    uint256 private constant ALLOWED_DEVIATION = 5e16; //5% in 1e18 / ETH scale
    address private constant USDC = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607; 

    uint256 private constant HUNDRED_USDC = 1e8;
    uint256 private constant HUNDRED_FIVE_USDC = 1e8 + 5e6;

    //Chainlink oracle source
    IAggregatorV3 public tokenPriceFeed;
    IAggregatorV3 public USDCPriceFeed;
    // ten to the power of the number of decimals given by the price feed
    uint256 private immutable oracleBase;

    uint256 private immutable swapSize;

    /**
    *    @notice Zero address checks done in Templater that generates DepositReceipt and so not needed here.
    **/
    constructor(string memory _name, 
                string memory _symbol, 
                address _router, 
                address _token0,
                address _token1,
                bool _stable,
                address _USDCPriceFeed,
                address _tokenPriceFeed,
                uint256 _swapSize,
                uint256 _heartbeat_token0,
                uint256 _heartbeat_token1) 
                DepositReceipt_Base(_heartbeat_token0, _heartbeat_token1)
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
        uint256 amountOut;
        //equality cannot be checked for strings so we hash them first.
        if (keccak256(token0Symbol) == keccak256(USDCSymbol)){
            require( IERC20Metadata(_token1).decimals() == 18, "Token does not have 18dp");
            (amountOut, ) = router.getAmountOut(_swapSize, _token1, USDC);
        }
        else
        {   
            bytes memory token1Symbol = abi.encodePacked(IERC20Metadata(_token1).symbol());
            
            require( keccak256(token1Symbol) == keccak256(USDCSymbol), "One token must be USDC");
            require( IERC20Metadata(_token0).decimals() == 18, "Token does not have 18dp");

            (amountOut, ) = router.getAmountOut(_swapSize, _token0, USDC);
            
            
        }
        //rough check to ensure we provide the right scale swapSize output of USDC
        require(amountOut >= HUNDRED_USDC, "swap amount too small");
        require(amountOut <= HUNDRED_FIVE_USDC, "swap amount too big");

        token0 = _token0;
        token1 = _token1;
        stable = _stable;

        USDCPriceFeed = IAggregatorV3(_USDCPriceFeed);
        tokenPriceFeed = IAggregatorV3(_tokenPriceFeed);

        uint256 USDCOracleDecimals = USDCPriceFeed.decimals();  //Chainlink USD oracles have 8d.p.
        require(USDCOracleDecimals == tokenPriceFeed.decimals());

        oracleBase = 10 ** USDCOracleDecimals;  //Chainlink USD oracles have 8d.p.
        
        //set the scale of the exchange swap used for priceLiquidity
        swapSize = _swapSize;

        pair = IPair(router.pairFor(_token0, _token1, _stable));
    }

   
    /**
    *  @notice this is used to price pooled Tokens by determining their underlying assets and then pricing these
    *  @notice using Chainlink price feeds and a Velodrome swap estimate to prevent flash loan exploits
    *  @dev each DepositReceipt has a bespoke valuation method, make sure it fits the tokens
    *  @dev each DepositReceipt's valuation method is sensitive to available liquidity keep this in mind as liquidating a pooled token by using the same pool will reduce overall liquidity

    */
    function priceLiquidity(uint256 _liquidity) external override view returns(uint256){
        uint256 token0Amount;
        uint256 token1Amount;
        (token0Amount, token1Amount) = viewQuoteRemoveLiquidity(_liquidity);
        
        uint256 value0;
        uint256 value1;
        if (token0 == USDC){
            //check swap value of about $100 of tokens to WETH to protect against flash loan attacks
            uint256 amountOut = pair.getAmountOut(swapSize, token1); //amount received by trade

            uint256 tokenOraclePrice = getOraclePrice(tokenPriceFeed, token1);
            uint256 USDCOraclePrice = getOraclePrice(USDCPriceFeed, USDC);
            //reduce amountOut to the value of one token in dollars in the same scale as tokenOraclePrice (1e8)
            uint256 valueOut = amountOut * USDCOraclePrice / (swapSize/BASE) / USDC_BASE; 

            //calculate acceptable deviations from oracle price
            
            uint256 lowerBound = (tokenOraclePrice * (BASE - ALLOWED_DEVIATION)) / BASE;
            uint256 upperBound = (tokenOraclePrice * (BASE + ALLOWED_DEVIATION)) / BASE;
            
            
            require(lowerBound < valueOut, "Price shift low detected");
            require(upperBound > valueOut, "Price shift high detected");

            //adjust the scale of USDC to match 18.d.p tokens
            value0 = token0Amount * USDCOraclePrice * SCALE_SHIFT;
            
            value1 = token1Amount * tokenOraclePrice;
        }
        //token1 must be USDC
        else {
            
            //check swap value of about $100 of tokens to WETH to protect against flash loan attacks
            uint256 amountOut = pair.getAmountOut(swapSize, token0); //amount received by trade
           
            uint256 tokenOraclePrice = getOraclePrice(tokenPriceFeed, token0);
            uint256 USDCOraclePrice = getOraclePrice(USDCPriceFeed, USDC);
            //reduce amountOut to the value of one token in dollars in the same scale as tokenOraclePrice (1e8)
            uint256 valueOut = amountOut * USDCOraclePrice / (swapSize/BASE) / USDC_BASE; 
            //calculate acceptable deviations from oracle price
            uint256 lowerBound = (tokenOraclePrice * (BASE - ALLOWED_DEVIATION)) / BASE;
            uint256 upperBound = (tokenOraclePrice * (BASE + ALLOWED_DEVIATION)) / BASE;
            
            require(lowerBound < valueOut, "Price shift low detected");
            require(upperBound > valueOut, "Price shift high detected");

            //adjust the scale of USDC to match 18.d.p tokens
            value1 = token1Amount * USDCOraclePrice * SCALE_SHIFT;
            
            value0 = token0Amount * tokenOraclePrice;
        }
        // because value0 and value1 are in the same scale we can reduce them to 1e18 scale after adding.
        return((value0 + value1)/oracleBase);
    }
}
