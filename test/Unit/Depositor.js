const { expect } = require("chai")
const { ethers } = require("hardhat")
const { helpers } = require("./testHelpers.js")

describe("Depositor contract", function () {
    const provider = ethers.provider;
    const stable = true;

    before(async function () {
        
        [owner, alice, bob, ...addrs] = await ethers.getSigners()
        Depositor = await ethers.getContractFactory("Depositor")
        Gauge = await ethers.getContractFactory("TESTGauge")
        TESTERC20Token = await ethers.getContractFactory("TESTERC20Token")
        DepositReceipt = await ethers.getContractFactory("DepositReceipt")
        TESTRouter = await ethers.getContractFactory("TESTRouter")
        

        depositReceipt = await DepositReceipt.deploy(
            "Deposit_Receipt",
            "DR")
        AMMToken = await TESTERC20Token.deploy("vAMM-token", "AMM")
        token0 = await TESTERC20Token.deploy("token0", "T0")
        token1 = await TESTERC20Token.deploy("token1", "T1")
        gauge = await Gauge.deploy(AMMToken.address)
        router = await TESTRouter.deploy()
        

        depositor = await Depositor.connect(owner).deploy(
            depositReceipt.address,
            AMMToken.address,
            gauge.address,
            router.address,
            token0.address,
            token1.address,
            stable)
        
        depositReceipt.connect(owner).addMinter(depositor.address)


    })

    beforeEach(async () => {
        snapshotId = await helpers.snapshot(provider)
        //console.log('Snapshotted at ', await provider.getBlockNumber())
    });
    
    afterEach(async () => {
        await helpers.revertChainSnapshot(provider, snapshotId)
        //console.log('Reset block heigh to ', await provider.getBlockNumber())
    });
    describe("Constructor", function (){
        it("Should set up the right addresses", async function (){
            expect( await depositor.depositReceipt() ).to.equal(depositReceipt.address)
            expect( await depositor.gauge() ).to.equal(gauge.address)
            expect( await depositor.AMMToken() ).to.equal(AMMToken.address)
            expect( await depositor.router() ).to.equal(router.address)
            expect( await depositor.token0() ).to.equal(token0.address)
            expect( await depositor.token1() ).to.equal(token1.address)
            expect( await depositor.stable() ).to.equal(stable)
            
        });
       
      });

    describe("depositToGauge", function (){
        it("Should deposit to gauge with right user call", async function (){
            const amount = ethers.utils.parseEther('353')
            before_gauge_tokens = await AMMToken.balanceOf(gauge.address)
            before_owner_tokens = await AMMToken.balanceOf(owner.address)

            AMMToken.approve(depositor.address, amount)
            await depositor.connect(owner).depositToGauge(amount)
            let NFT_id = 1

            //after transaction checks
            after_gauge_tokens = await AMMToken.balanceOf(gauge.address)
            after_owner_tokens = await AMMToken.balanceOf(owner.address)
            after_nft_pooled_tokens = await depositReceipt.pooledTokens(NFT_id)
        
            expect(after_gauge_tokens).to.equal(before_gauge_tokens.add(amount))
            expect(after_owner_tokens).to.equal(before_owner_tokens.sub(amount))
            expect(after_nft_pooled_tokens).to.equal(amount)
            expect(await depositReceipt.ownerOf(NFT_id)).to.equal(owner.address)

            
        });

        it("Should fail if AMMToken lacks approval", async function (){
            const amount = ethers.utils.parseEther('353')
            await expect(depositor.connect(owner).depositToGauge(amount)).to.be.revertedWith("ERC20: insufficient allowance")
            
        });

        it("Should fail if called by wrong user ", async function (){
            const amount = ethers.utils.parseEther('353')
            await expect(depositor.connect(bob).depositToGauge(amount)).to.be.revertedWith("Ownable: caller is not the owner")
            
        });
        
    });

    describe("withdrawFromGauge", function (){
        const NFT_id = 1  
        const amount = ethers.utils.parseEther('353')  
        
        it("Should withdraw from gauge with right user call", async function (){
            //setup deposit first
              
            AMMToken.approve(depositor.address, amount)
            await depositor.connect(owner).depositToGauge(amount)
            rewards_address = await gauge.FakeRewards()

            before_NFT_owner = await depositReceipt.ownerOf(NFT_id)
            expect(before_NFT_owner).to.equal(owner.address)
            before_owner_tokens = await AMMToken.balanceOf(owner.address)

            await depositReceipt.connect(owner).approve(depositor.address, NFT_id)
            await depositor.connect(owner).withdrawFromGauge(NFT_id, [rewards_address])

            //after transaction checks
            after_owner_NFT_count = await depositReceipt.balanceOf(owner.address)
            expect(after_owner_NFT_count).to.equal(0)
            await expect(depositReceipt.ownerOf(NFT_id)).to.be.revertedWith("ERC721: invalid token ID")
            

            after_owner_tokens = await AMMToken.balanceOf(owner.address)
            expect(after_owner_tokens).to.equal(before_owner_tokens.add(amount))
            
        });

        it("Should fail if user lacks depositReceipts", async function (){
             //setup deposit first     
             AMMToken.approve(depositor.address, amount)
             await depositor.connect(owner).depositToGauge(amount)
             rewards_address = await gauge.FakeRewards()
 
             before_NFT_owner = await depositReceipt.ownerOf(NFT_id)
             expect(before_NFT_owner).to.equal(owner.address)
             
            //overloaded function so different calling structure
             await depositReceipt["safeTransferFrom(address,address,uint256)"](owner.address, alice.address, NFT_id)
             after_NFT_owner = await depositReceipt.ownerOf(NFT_id)
             expect(after_NFT_owner).to.equal(alice.address)
             await expect(depositor.connect(owner).withdrawFromGauge(NFT_id, [rewards_address])).to.be.revertedWith("ERC721: caller is not token owner or approved")
 
        });

        it("Should fail if called by wrong user ", async function (){
            rewards_address = await gauge.FakeRewards()
            //setup deposit first
              
            AMMToken.approve(depositor.address, amount)
            await depositor.connect(owner).depositToGauge(amount)

            await expect(depositor.connect(bob).withdrawFromGauge(NFT_id, [rewards_address])).to.be.revertedWith('ERC721: caller is not token owner or approved')
            
        });

        
        
    });

    describe("claimRewards", function (){

        it("Should withdraw rewards from gauge with right user call", async function (){
            //setup deposit first
            const amount = ethers.utils.parseEther('353')      
            AMMToken.approve(depositor.address, amount)
            await depositor.connect(owner).depositToGauge(amount)
            //set up already deployed rewards token contract
            rewards_address = await gauge.FakeRewards()

            const abi = [
                "function balanceOf(address account) view returns(uint256)"
            ]
            rewardToken = new ethers.Contract(rewards_address, abi, provider);

            before_owner_rewards = await rewardToken.connect(owner).balanceOf(owner.address)
            expect(before_owner_rewards).to.equal(0)
            before_depositor_rewards = await rewardToken.balanceOf(depositor.address)
            expect(before_depositor_rewards).to.equal(0)
            let expected_rewards = await depositor.viewPendingRewards(rewardToken.address)

            await depositor.connect(owner).claimRewards([rewards_address])

            
            after_owner_rewards = await rewardToken.balanceOf(owner.address)
            expect(after_owner_rewards).to.equal(expected_rewards)
            //no rewards should be left in the depositor
            after_depositor_rewards = await rewardToken.balanceOf(depositor.address)
            expect(after_depositor_rewards).to.equal(0)
            
        });

        it("Should fail if called with empty data ", async function (){
            await expect(depositor.connect(owner).claimRewards([])).to.be.revertedWith("Empty tokens array")
            
        });

        it("Should fail if called by wrong user ", async function (){
            rewards_address = await gauge.FakeRewards()
            await expect(depositor.connect(bob).claimRewards([rewards_address])).to.be.revertedWith("Ownable: caller is not the owner")
            
        });

        
        
    });

    describe("viewPendingRewards", function (){

        it("Should return pending rewards of only reward eligible tokens", async function (){
            //setup deposit first
            const amount = ethers.utils.parseEther('353')      
            AMMToken.approve(depositor.address, amount)
            await depositor.connect(owner).depositToGauge(amount)
            //set up already deployed rewards token contract
            rewards_address = await gauge.FakeRewards()

            const abi = [
                "function balanceOf(address account) view returns(uint256)"
            ]
            rewardToken = new ethers.Contract(rewards_address, abi, provider);

            let expected_rewards = await depositor.viewPendingRewards(rewardToken.address)
            let gauge_rewards = await gauge.earned(rewardToken.address, owner.address)
            expect(expected_rewards).to.equal(gauge_rewards)

            //test unknown token address
            let expected_rewards_unknown = await depositor.viewPendingRewards(bob.address)
            let gauge_rewards_unknown = await gauge.earned(bob.address, owner.address)
            expect(expected_rewards_unknown).to.equal(0)
            expect(expected_rewards_unknown).to.equal(gauge_rewards_unknown)

            
            
        });
    });
})
