const { expect } = require("chai")
const { ethers } = require("hardhat")
const { helpers } = require("../helpers/testHelpers.js")

describe.only("Templater contract", function () {
    const provider = ethers.provider;
    

    before(async function () {
        
        [owner, alice, bob, ...addrs] = await ethers.getSigners()
        Templater = await ethers.getContractFactory("Templater")
        TESTERC20Token = await ethers.getContractFactory("TESTERC20Token")
        PriceOracle = await ethers.getContractFactory("TESTAggregatorV3")

        tokenA = await TESTERC20Token.deploy("TokenA", "TA")
        tokenB = await TESTERC20Token.deploy("TokenB", "TB")
        priceOracle = await PriceOracle.deploy()

        templater = await Templater.deploy(
            tokenA.address,
            tokenB.address,
            true,
            alice.address,
            owner.address,
            bob.address,
            priceOracle.address)


    })

    beforeEach(async () => {
        snapshotId = await helpers.snapshot(provider)
        //console.log('Snapshotted at ', await provider.getBlockNumber())
    });
    
    afterEach(async () => {
        await helpers.revertChainSnapshot(provider, snapshotId)
        //console.log('Reset block heigh to ', await provider.getBlockNumber())
    });

    describe("makeNewDepositor", function (){
        it("Should allow anyone to set up a new Depositer", async function (){
            await expect(templater.connect(owner).makeNewDepositor()).to.emit(templater, "newDepositorMade")
            await expect(templater.connect(alice).makeNewDepositor()).to.emit(templater, "newDepositorMade")
            //how to check for correct emitted addresses given we don't know prior? (without using create2)
        });
        it("Should revert if called twice by the same user", async function (){
            await templater.connect(alice).makeNewDepositor()
            await expect(templater.connect(alice).makeNewDepositor()).to.be.revertedWith("User already has Depositor")
            //how to check for correct emitted addresses given we don't know prior? (without using create2)
        });
      });
})
