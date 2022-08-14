pragma solidity =0.8.9;

interface IRouter{
    function quoteRemoveLiquidity(address tokenA, address tokenB, bool stable, uint256 liquidity) external view returns(uint256, uint256);
    
}