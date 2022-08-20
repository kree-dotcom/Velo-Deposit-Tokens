# VELO Deposit Tokens

This set of contracts is a simple wraparound depositor that enables a user to deposit into a VELO staking gauge and receive their rewards while also generating a deposit receipt that can be used on other protocols as collateral. The deposit receipts are  ERC721s that are granted on deposits of  pooled AMM tokens.

## Fairly valuing deposits
Integrating services must make their own decisions on how to value this token but a simplistic example is included with the deposit receipt contract. In this method it is assumed each token is paired directly with USDC which is then valued at $1. Then the same pool is used to convert the value of the other token via a swap. This has the advantage of applying slippage to larger trade amounts reflecting the reduced exchange rate that is likely on liquidation. However care must be taken as if the quantity the deposit receipt represents is a significant quantity of the overall pooled tokens it's removal will then impact the conversion rate it will receive after removal. Accrued rewards (in any token) are not counted by the default method of valuation.

## Acceptable tokens
Pool tokens may either be stable or volatile VELO pool tokens, each different pool token must have it's own set of contracts deployed. Care must be taken to ensure the pricing system is relevant to the tokens deployed. 
the pooled tokens. 

## Actor isolation
Each depositor is isolated in their own contract, only they can deposit tokens. This reduces the risk vector of comingling funds and is possible due to the low gas costs of Optimism. An additional benefit of this design is simplifying who is owed which rewards as each depositor can simply claim all acrrued rewards in their contract. 
To enable liquidation of the deposit receipt ERC721s anyone can withdraw pooled AMM tokens from a depositor contract so long as they own an NFT deposit receipt 
that is related to that depositor. Only the original depositor can withdraw any accrued rewards.
