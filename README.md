# VELO Deposit Tokens

This set of contracts is a simple wraparound depositor that enables a user to deposit into a VELO staking gauge and receive their rewards while also generating a deposit receipt that can be used on other protocols as collateral. The deposit receipt is a standardized ERC20 token that is granted one for one to deposited pool tokens. Integrating services must make their own decisions on how to value this token. Pool tokens may either be stable or volatile VELO pool tokens, each different pool token must have it's own set of contracts deployed.

Each depositor is isolated in their own contract, this reduces the risk vector of comingling funds and is possible due to the low gas costs of Optimism. An additional benefit of this design is simplifying who is owed which rewards as each depositor can simply claim all acrrued rewards in their contract. 
