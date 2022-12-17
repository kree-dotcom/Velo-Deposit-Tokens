pragma solidity =0.8.9;

interface IPair{
    function getAmountOut(uint256 amountIn, address tokenIn) external view returns(uint256 amount); 
    
}