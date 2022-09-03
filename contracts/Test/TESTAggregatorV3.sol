pragma solidity 0.8.9; //the AccessControlledOffchainAggregator actually uses ^0.7.1 but as this is an interface this is ok.

import "./TESTAccessControlledOffchainAggregator.sol";
contract TESTAggregatorV3 {

    TESTAccessControlledOffchainAggregator public aggregator;

    constructor() {
        aggregator = new TESTAccessControlledOffchainAggregator();
    }

    function decimals() external view returns(uint8){
        return(8);
    }

    function minPrice() external view returns(int192){
        return(1000000); //$0.01 in oracle scale
    }
        

    function maxPrice() external view returns(int192){
        return(100000000000); //$1000.00 in oracle scale
    }

    function latestRoundData() external view returns(
        uint80,
        int, 
        uint256, 
        uint256, 
        uint80 ){
        return(
            0,
            110000000, //$1.1 in oracle scale
            block.timestamp -10, //round started at
            block.timestamp, //updatedAt
            0
        );
    }
        
}
