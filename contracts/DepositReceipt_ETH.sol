pragma solidity =0.8.9;

import "./DepositReceipt_Base.sol";

contract DepositReceipt_ETH is  DepositReceipt_Base {
    
    //Price deviation limit when checking pool exchange rate against Chainlink Oracle
    uint256 private constant ALLOWED_DEVIATION = 5e16; //5% in 1e18 / ETH scale
    //deployed address of WETH on Optimism Mainnet
    address private constant WETH = 0x4200000000000000000000000000000000000006;
    
    //Chainlink oracle sources
    IAggregatorV3 public ETHPriceFeed;
    IAggregatorV3 public tokenPriceFeed;
    
    // ten to the power of the number of decimals given by both price feeds
    uint256 private immutable oracleBase;
    
    uint256 private immutable swapSize; //amount swapped to validate exchange rate, due to constructor restrictions we know both tokens are 18.d.p

    /**
    *    @notice Zero address checks done in Templater that generates DepositReceipt and so not needed here.
    **/
    constructor(string memory _name, 
                string memory _symbol, 
                address _router, 
                address _token0,
                address _token1,
                bool _stable,
                address _ETHPriceFeed,
                address _tokenPriceFeed,
                uint256 _swapSize,
                uint256 _heartbeat_token0,
                uint256 _heartbeat_token1) 
                DepositReceipt_Base(_heartbeat_token0, _heartbeat_token1)
                ERC721(_name, _symbol){
        
        require(_swapSize > 0, "swapSize not set");
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
        
        bytes memory WETHSymbol = abi.encodePacked("WETH");
        bytes memory token0Symbol = abi.encodePacked(IERC20Metadata(_token0).symbol());
        //equality cannot be checked for strings so we hash them first.
        if (keccak256(token0Symbol) == keccak256(WETHSymbol)){
            require( IERC20Metadata(_token1).decimals() == 18, "Token does not have 18dp");

            //because the value of WETH is not stable like USDC we cannot do the same setup exchange rate check used in depositReceipt_USDC
        }
        else
        {   
            bytes memory token1Symbol = abi.encodePacked(IERC20Metadata(_token1).symbol());
            
            require( keccak256(token1Symbol) == keccak256(WETHSymbol), "One token must be WETH");
            require( IERC20Metadata(_token0).decimals() == 18, "Token does not have 18dp");
            
        }

        token0 = _token0;
        token1 = _token1;
        stable = _stable;
    
        //fetch details for ETH price feed
        ETHPriceFeed = IAggregatorV3(_ETHPriceFeed);
        tokenPriceFeed = IAggregatorV3(_tokenPriceFeed);
       
        uint256 ETHOracleDecimals = ETHPriceFeed.decimals();  //Chainlink USD oracles have 8d.p.
        require(ETHOracleDecimals == tokenPriceFeed.decimals());
        // because we have checked both oracles have the same amount of decimals we only store one OracleBase
        oracleBase = 10 ** ETHOracleDecimals;
        
        //set the scale of the exchange swap used for priceLiquidity
        swapSize = _swapSize;

        pair = IPair(router.pairFor(_token0, _token1, _stable));
        
    }

   /**
    *  @notice this is used to price pooled Tokens by determining their underlying assets and then pricing these
    *  @notice the two ways to do this are to price to USDC as  a dollar equivalent or to ETH then use Chainlink price feeds
    *  @dev each DepositReceipt has a bespoke valuation method, make sure it fits the tokens
    *  @dev each DepositReceipt's valuation method is sensitive to available liquidity keep this in mind as liquidating a pooled token by using the same pool will reduce overall liquidity

    */
    function priceLiquidity(uint256 _liquidity) external override view returns(uint256){
        uint256 token0Amount;
        uint256 token1Amount;
        (token0Amount, token1Amount) = viewQuoteRemoveLiquidity(_liquidity);
        
        uint256 value0;
        uint256 value1;
        if (token0 == WETH){
            //check swap value of about $100 of tokens to WETH to protect against flash loan attacks
            uint256 amountOut = pair.getAmountOut(swapSize, token1); //amount received by trade

            uint256 tokenOraclePrice = getOraclePrice(tokenPriceFeed, token1);
            uint256 ETHOraclePrice = getOraclePrice(ETHPriceFeed, WETH);
            //reduce amountOut to the value of one token in dollars in the same scale as tokenOraclePrice (1e8)
            uint256 valueOut = amountOut * ETHOraclePrice / (swapSize/BASE) / BASE; 

            //calculate acceptable deviations from oracle price
            
            uint256 lowerBound = (tokenOraclePrice * (BASE - ALLOWED_DEVIATION)) / BASE;
            uint256 upperBound = (tokenOraclePrice * (BASE + ALLOWED_DEVIATION)) / BASE;
            
            
            require(lowerBound < valueOut, "Price shift low detected");
            require(upperBound > valueOut, "Price shift high detected");

            value0 = token0Amount * ETHOraclePrice;
            
            value1 = token1Amount * tokenOraclePrice;
        }
        //token1 must be WETH
        else {
            
            //check swap value of about $100 of tokens to WETH to protect against flash loan attacks
            uint256 amountOut = pair.getAmountOut(swapSize, token0); //amount received by trade
           
            uint256 tokenOraclePrice = getOraclePrice(tokenPriceFeed, token0);
            uint256 ETHOraclePrice = getOraclePrice(ETHPriceFeed, WETH);
            //reduce amountOut to the value of one token in dollars in the same scale as tokenOraclePrice (1e8)
            uint256 valueOut = amountOut * ETHOraclePrice / (swapSize/BASE) / BASE; 
            //calculate acceptable deviations from oracle price
            uint256 lowerBound = (tokenOraclePrice * (BASE - ALLOWED_DEVIATION)) / BASE;
            uint256 upperBound = (tokenOraclePrice * (BASE + ALLOWED_DEVIATION)) / BASE;
            
            require(lowerBound < valueOut, "Price shift low detected");
            require(upperBound > valueOut, "Price shift high detected");

            value1 = token1Amount * ETHOraclePrice;
            
            value0 = token0Amount * tokenOraclePrice;
        }
        // because value0 and value1 are in the same scale we can reduce them to 1e18 scale after adding.
        return((value0 + value1)/oracleBase);
    }
}
