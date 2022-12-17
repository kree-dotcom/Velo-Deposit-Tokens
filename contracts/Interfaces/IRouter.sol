pragma solidity =0.8.9;

interface IRouter{
    function quoteRemoveLiquidity(address tokenA, address tokenB, bool stable, uint256 liquidity) external view returns(uint256, uint256);
    function getAmountOut(uint256 amountIn, address tokenIn, address tokenOut) external view returns(uint256 amount, bool stable);
    function pairFor(address token0, address token1, bool stable) external view returns(address);
    
}