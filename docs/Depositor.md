# Depositor.sol Purpose and functions
The Depositor is how the Velo Deposit Token system interacts with the Velodrome Gauge. It deposits to the Gauge on the user's behalf and grants them a NFT receipt, DepositReceipt that allows them to then use that deposit as collateral on Isomorph.

## constructor

## onERC721Received
When minting new DepositReceipts NFTs they are first minted to the Depositor so we must include this function to enable the Depositor to receive these.


## depositToGauge
This function can only be called by the OWNER. The OWNER calls this function to deposit Velodrome pooledTokens into a Velodrome gauge to earn reward tokens. Once this is done we mint a new DepositReceipt NFT which records how many pooledTokens they have deposited in the Depositor. 
This NFT is then transfered to the msg.sender.


## partialWithdrawFromGauge
This function can be called by anyone. However to split or burn the inputted NFT the caller must either own the NFT or have added the Depositor contract to the NFTs approved list. It first uses the DepositReceipt's split function to split the given NFT into two NFTs, it then requests to withdraw the new NFT, leaving the old NFT still in the msg.sender's wallet. 


## multiWithdrawFromGauge
This function can be called by anyone. To improve user experience we allow a valid NFT holder/approved user (see withdrawFromGauge for details) to withdraw multiple DepositReceipt NFTs in one transaction. First we process all NFTs being fully withdrawn by passing their data to withdrawFromGauge. Then if any NFT is being partially withdrawn we handle that seperately. It is assumed that only one NFT is being withdrawn partially for simplicity. As the loop may be gas intensive it is possible this call may fail due to reaching the block gas limit. This is not a big problem as the call can be repeated with less tokens or it's behaviour can be mimicked by withdrawFromGauge and partialWithdrawFromGauge.


## withdrawFromGauge
This function can be called by anyone. However to burn the inputted NFT the caller must either own the NFT or have added the Depositor contract to the NFTs approved list. By this way we prevent arbitrary draining of the underlying pool tokens. The only way to get the DepositReceipts is if you are the original depositing OWNER, the OWNER has transfered these to you (they have no reason to do so) or if a loan on Isomorph has been liquidated and the collateral DepositReceipt NFT has been given to the liquidator for paying off the user's loan.

We place a getReward call prior to withdraw, this is not necessary but was originally advised. Then we call gauge.withdraw for amount before sending that full amount to the msg.sender. 


## claimRewards
This function can only be called by the OWNER. It takes an array of reward token addresses and claims them from the gauge. It then transfers the complete balance of the Depositor contract in each specified reward token to the msg.sender. We use safeTransfer here even if it is not strictly needed as we have no storage balance updates, if a reward token causes a revert for some reason the call can be repeated minus that token address, as calls to gauge.getReward will succeed even if there are no rewards payable. As only the Depositor OWNER can call this function we do not need to validate incoming token addresses to prevent malicious behaviour.


## viewPendingRewards
This view function is a passthrough to the gauge, it displays how many reward tokens have accrued to the Depositor contract that can then be claimed by the Depositor owner using claimRewards. It must be called per each reward token address the user is interested in.
