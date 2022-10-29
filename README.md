# VELO Deposit Tokens

This set of contracts is a simple wraparound depositor that enables a user to deposit into a VELO staking gauge and receive their rewards while also generating a deposit receipt that can be used on other protocols as collateral. The deposit receipts are  ERC721s that are granted on deposits of  pooled AMM tokens.

## Fairly valuing deposits
Integrating services must make their own decisions on how to value this token but a simplistic example is included with the deposit receipt contract. In this method it is assumed each token is paired directly with USDC which is then valued at $1. The withdrawal quantity of each token is received from the Velodrome router, then the non-USDC token has its quantity converted to a Chainlink sourced USD value.
Some protections are in place to prevent a stale pricefeed being used. Accrued rewards (in any token) are not counted by the default method of valuation.

## Acceptable tokens
Pool tokens may either be stable or volatile VELO pool tokens, each different pool token must have its own set of contracts deployed. Care must be taken to ensure the pricing system is relevant to the tokens deployed. 


## Actor isolation
Each depositor is isolated in their own contract, only they can deposit tokens. This reduces the risk vector of comingling funds and is possible due to the low gas costs of Optimism. An additional benefit of this design is simplifying who is owed which rewards as each depositor can simply claim all acrrued rewards in their contract. 
To enable liquidation of the deposit receipt ERC721s anyone can withdraw pooled AMM tokens from a depositor contract so long as they own an NFT deposit receipt 
that is related to that depositor. Only the original depositor can withdraw any accrued rewards.


## Tests and coverage

Tests are a mixture of unit and integeration tests as is fit. To run the tests:

- Clone the repo
- run yarn install in the main directory to install required packages
- Connect API endpoints needed for integration testing using the .env file. See sample.env for details.
- Run tests using yarn hardhat test


Coverage is as follows:

File                 |  % Stmts | % Branch |  % Funcs |  % Lines |Uncovered Lines |
---------------------|----------|----------|----------|----------|----------------|
 contracts/          |      100 |       98 |      100 |      100 |                |
  DepositReceipt.sol |      100 |      100 |      100 |      100 |                |
  Depositor.sol      |      100 |     87.5 |      100 |      100 |                |
  Templater.sol      |      100 |      100 |      100 |      100 |                |
All files            |      100 |       98 |      100 |      100 |                |

