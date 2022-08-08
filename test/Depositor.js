const { expect } = require("chai")
const { ethers } = require("hardhat")
const { helpers } = require("./testHelpers.js")

describe("Depositor contract", function () {
    const provider = ethers.provider;

    before(async function () {
        
        [owner, alice, bob, ...addrs] = await ethers.getSigners()
        Depositor = await ethers.getContractFactory("Depositor")
        Gauge = await ethers.getContractFactory("TESTGauge")
        TESTERC20Token = await ethers.getContractFactory("TESTERC20Token")
        DepositReceipt = await ethers.getContractFactory("DepositReceipt")
        

        depositReceipt = await DepositReceipt.deploy(
            "Deposit_Receipt",
            "DR")
        AMMToken = await TESTERC20Token.deploy("vAMM-token", "AMM")
        gauge = await Gauge.deploy(AMMToken.address)

        depositor = await Depositor.connect(owner).deploy(
            depositReceipt.address,
            AMMToken.address,
            gauge.address)
        
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
            
        });
       
      });

    describe("depositToGauge", function (){
        it("Should deposit to gauge with right user call", async function (){
            const amount = ethers.utils.parseEther('353')
            before_gauge_tokens = await AMMToken.balanceOf(gauge.address)
            before_owner_tokens = await AMMToken.balanceOf(owner.address)

            AMMToken.approve(depositor.address, amount)
            await depositor.connect(owner).depositToGauge(amount)

            //after transaction checks
            after_gauge_tokens = await AMMToken.balanceOf(gauge.address)
            after_owner_tokens = await AMMToken.balanceOf(owner.address)
            after_owner_receipt = await depositReceipt.balanceOf(owner.address)
            expect(after_gauge_tokens).to.equal(before_gauge_tokens.add(amount))
            expect(after_owner_tokens).to.equal(before_owner_tokens.sub(amount))
            expect(after_owner_receipt).to.equal(amount)

            
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

        
        it("Should withdraw from gauge with right user call", async function (){
            //setup deposit first
            const amount = ethers.utils.parseEther('353')      
            AMMToken.approve(depositor.address, amount)
            await depositor.connect(owner).depositToGauge(amount)
            rewards_address = await gauge.FakeRewards()

            before_owner_receipt = await depositReceipt.balanceOf(owner.address)
            expect(before_owner_receipt).to.equal(amount)
            before_owner_tokens = await AMMToken.balanceOf(owner.address)

            await depositor.connect(owner).withdrawFromGauge(amount, [rewards_address])

            //after transaction checks
            after_owner_receipt = await depositReceipt.balanceOf(owner.address)
            expect(after_owner_receipt).to.equal(before_owner_receipt.sub(amount))
            after_owner_tokens = await AMMToken.balanceOf(owner.address)
            expect(after_owner_tokens).to.equal(before_owner_tokens.add(amount))
            
        });

        it("Should fail if user lacks depositReceipts", async function (){
             //setup deposit first
             const amount = ethers.utils.parseEther('353')      
             AMMToken.approve(depositor.address, amount)
             await depositor.connect(owner).depositToGauge(amount)
             rewards_address = await gauge.FakeRewards()
 
             before_owner_receipt = await depositReceipt.balanceOf(owner.address)
             expect(before_owner_receipt).to.equal(amount)
             before_owner_tokens = await AMMToken.balanceOf(owner.address)
            
             await depositReceipt.connect(owner).transfer(alice.address, amount)
             await expect(depositor.connect(owner).withdrawFromGauge(amount, [rewards_address])).to.be.revertedWith("ERC20: burn amount exceeds balance")
 
        });

        it("Should fail if called by wrong user ", async function (){
            const amount = ethers.utils.parseEther('353')
            rewards_address = await gauge.FakeRewards()

            await expect(depositor.connect(bob).withdrawFromGauge(amount, [rewards_address])).to.be.revertedWith("Ownable: caller is not the owner")
            
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
