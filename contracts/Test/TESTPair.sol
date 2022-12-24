pragma solidity =0.8.9;



contract TESTPair {
    address USDC = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;


    function getAmountOut(uint256 amountIn, address tokenIn) external view returns(uint256 amount, bool stable){
        //return different values to make unit test error detection easier
        if(tokenIn == USDC){
            return((amountIn *3) /2, true); //return 1.5x amountIn
        }
        else{
            return((amountIn *3)/5, true); //return 0.6x amountIn
        }
    } 

}