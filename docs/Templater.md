# Templater.sol Purpose and functions

The Templater is responsible for creating a pooledToken pair's DepositReceipt and creating new instances of the Depositor. A new instance of the Depositor is made for each new address interacting with the Templater.

## constructor
Only templaters made by Isomorph should have their DepositReceipts added as collateral to Isomorph as a lot of the data is set via the constructor and so possible to set maliciously if done by another user. The naming structor of the DepositReceipts name and symbol are deterministic, decided by the tokens it represents and following the same naming structure as the pooledTokens available on Velodrome. 


These strings are only used by the user, inide Isomorph collaterals are identified by their address and so there should be no risk of similar or the same named DepositReceipts causing issues should they ever occur. 

The Templater creates a new instance of the DepositReceipt on construction, it becomes the ADMIN of this DepositReceipt, allowing it to add new MINTERs.


## makeNewDepositor
This function is called every time a new address wishes to deposit pooledTokens and generate a new DepositReceipt. It creates a new instance of Depositor linked to the new address. This Depositor is linked to the DepositReceipt that Templater made in the constructor. 


All Depositors are added as MINTERs of the DepositReceipt NFTs. We first check the UserToDepositor mapping is zero to ensure the user does not already have a linked Depositor, this is to prevent overwriting where an existing Depositor is which would be a bad user experience. The ownership of the Depositor is initially set as the Templater so we transfer it to the msg.sender to enable them to call certain owner only functions in it.

