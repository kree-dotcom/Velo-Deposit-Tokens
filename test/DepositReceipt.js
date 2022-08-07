const { expect } = require("chai")
const { ethers } = require("hardhat")
const { helpers } = require("./testHelpers.js")

describe("DepositReceipt contract", function () {
    const provider = ethers.provider;
    const ADMIN_ROLE = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("ADMIN_ROLE"));
    const MINTER_ROLE = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("MINTER_ROLE"));

    before(async function () {
        
        [owner, alice, bob, ...addrs] = await ethers.getSigners()
        DepositReceipt = await ethers.getContractFactory("DepositReceipt")
        

        depositReceipt = await DepositReceipt.deploy(
            "Deposit_Receipt",
            "DR")


    })

    beforeEach(async () => {
        snapshotId = await helpers.snapshot(provider)
        //console.log('Snapshotted at ', await provider.getBlockNumber())
    });
    
    afterEach(async () => {
        await helpers.revertChainSnapshot(provider, snapshotId)
        //console.log('Reset block heigh to ', await provider.getBlockNumber())
    });
    describe("Admin role", function (){
        it("Should add Msg.sender as ADMIN", async function (){
            expect( await depositReceipt.hasRole(ADMIN_ROLE, owner.address) ).to.equal(true)
            
        });
        it("should not let Admin role addresses mint", async function (){
            expect( await depositReceipt.hasRole(MINTER_ROLE, owner.address) ).to.equal(false)
            await expect(depositReceipt.connect(owner).mint(1)).to.be.revertedWith("Caller is not a minter")
        });
      });

    describe("Minting", function (){
        it("Should allow only ADMIN_ROLE address to add MINTER_ROLE and emit event", async function (){
            await expect(depositReceipt.connect(owner).addMinter(bob.address)).to.emit(depositReceipt, "AddNewMinter").withArgs(bob.address, owner.address)
            await expect(depositReceipt.connect(bob).addMinter(alice.address)).to.revertedWith("Caller is not an admin")
        });

        it("Should only allow MINTER_ROLE address to mint/burn", async function (){
            await depositReceipt.connect(owner).addMinter(bob.address)
            const amount = ethers.utils.parseEther('353');
            await depositReceipt.connect(bob).mint(amount)
            erc20_amount = await depositReceipt.balanceOf(bob.address)
            expect(erc20_amount).to.equal(amount)
            await expect(depositReceipt.connect(alice).mint(1)).to.be.revertedWith("Caller is not a minter")

            
        });
      });
})
