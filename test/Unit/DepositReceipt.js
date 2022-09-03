const { expect } = require("chai")
const { ethers } = require("hardhat")
const { helpers } = require("../helpers/testHelpers.js")
const { addresses } = require("../helpers/deployedAddresses.js")

describe("DepositReceipt contract", function () {
    const provider = ethers.provider;
    const ADMIN_ROLE = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("ADMIN_ROLE"))
    const MINTER_ROLE = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("MINTER_ROLE"))

    before(async function () {
        
        [owner, alice, bob, ...addrs] = await ethers.getSigners()
        DepositReceipt = await ethers.getContractFactory("DepositReceipt")
        Router = await ethers.getContractFactory("TESTRouter")
        PriceOracle = await ethers.getContractFactory("TESTAggregatorV3")
        router = await Router.deploy()
        priceOracle = await PriceOracle.deploy()

        depositReceipt = await DepositReceipt.deploy(
            "Deposit_Receipt",
            "DR",
            router.address,
            alice.address,
            bob.address,
            true,
            priceOracle.address
            )

        //duplicate used for one pricing test
        depositReceipt2 = await DepositReceipt.deploy(
                "Deposit_Receipt",
                "DR",
                router.address,
                addresses.optimism.USDC,
                bob.address,
                true,
                priceOracle.address
                )

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
            await expect(depositReceipt.connect(owner).safeMint(1)).to.be.revertedWith("Caller is not a minter")
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
            await depositReceipt.connect(bob).safeMint(amount)
            let nft_id = 1
            expect( await depositReceipt.ownerOf(nft_id)).to.equal(bob.address)
            expect( await depositReceipt.pooledTokens(nft_id)).to.equal(amount)
    
            await expect(depositReceipt.connect(alice).safeMint(1)).to.be.revertedWith("Caller is not a minter")

            await expect(depositReceipt.connect(alice).burn(nft_id)).to.be.revertedWith("Caller is not a minter")
        });
      });

      describe("Splitting NFTs", function (){
        

        it("Should only allow owner to split the NFT", async function (){
            await depositReceipt.connect(owner).addMinter(bob.address)
            const amount = ethers.utils.parseEther('353');
            const BASE = ethers.utils.parseEther('1');
            await depositReceipt.connect(bob).safeMint(amount)
            let nft_id = 1
            let new_nft_id = nft_id +1
            let split = ethers.utils.parseEther('0.53'); //53%
            expect( await depositReceipt.ownerOf(nft_id)).to.equal(bob.address)
            expect( await depositReceipt.pooledTokens(nft_id)).to.equal(amount)
        
            //call split here with wrong user
            await expect(depositReceipt.connect(owner).split(nft_id, split)).to.be.revertedWith('only the owner can split their NFT')

            //call split with right user
            await expect(depositReceipt.connect(bob).split(nft_id, split)).to.emit(depositReceipt, "NFTSplit").withArgs(nft_id, new_nft_id)
            //check other two emitted events here too

            //check new NFT details
            expect( await depositReceipt.ownerOf(new_nft_id)).to.equal(bob.address)
            let new_pooled_tokens = amount.mul(split).div(BASE)
            expect( await depositReceipt.pooledTokens(new_nft_id)).to.equal(new_pooled_tokens)
            //check old NFT details
            expect( await depositReceipt.ownerOf(nft_id)).to.equal(bob.address)
            expect( await depositReceipt.pooledTokens(nft_id)).to.equal(amount.sub(new_pooled_tokens))
            

        });

        it("Should reject split percentages not in [0,100)", async function (){
            await depositReceipt.connect(owner).addMinter(bob.address)
            const amount = ethers.utils.parseEther('353');
            const BASE = ethers.utils.parseEther('1');
            await depositReceipt.connect(bob).safeMint(amount)
            let nft_id = 1
            let new_nft_id = nft_id +1
            let bad_split = ethers.utils.parseEther('1'); //100%
            let bad_split_2 = ethers.utils.parseEther('2'); //200%
        
            //call split here, check correct functioning
            await expect(depositReceipt.connect(owner).split(nft_id, bad_split)).to.be.revertedWith('split must be less than 100%')

            await expect(depositReceipt.connect(owner).split(nft_id, bad_split_2)).to.be.revertedWith('split must be less than 100%')

        });
      });

      describe("Pricing Pooled Tokens", function (){
        

        it("Should quote removable liquidity correctly", async function (){
            //pass through function so this only checks inputs haven't been mismatched
            const liquidity = ethers.utils.parseEther('1'); 
            
            let output = await depositReceipt.viewQuoteRemoveLiquidity(liquidity)
            
            let expected_output = await router.quoteRemoveLiquidity(alice.address, bob.address, true, liquidity)
    
            expect(output[0]).to.equal(expected_output[0])
            expect(output[1]).to.equal(expected_output[1])
            

        });

        it("Should price liquidity right depending on which token USDC is", async function (){
            const liquidity = ethers.utils.parseEther('1'); 
            let value = await depositReceipt.priceLiquidity(liquidity)
            //as token0 is not USDC we have assumed token1 is
            let outputs = await depositReceipt.viewQuoteRemoveLiquidity(liquidity)
            console.log("removables ", outputs[0].toString(), " ", outputs[1].toString())
            let value_token0 = outputs[0].mul(11).div(10)
            let value_token1 = outputs[1]
            let expected_value = ( value_token0 ).add( value_token1 )
            expect(value).to.equal(expected_value)

            
            //in the second instance USDC is token0
            let value2 = await depositReceipt2.priceLiquidity(liquidity)
            //as token0 is not USDC we have assumed token1 is
            let outputs2 = await depositReceipt2.viewQuoteRemoveLiquidity(liquidity)
            value_token0 = outputs2[0]
            value_token1 = outputs2[1].mul(11).div(10)
            let expected_value2 = ( value_token0 ).add(value_token1 )
            expect(value2).to.equal(expected_value2)
            
            
        });

        it.only("Should revert if Price is outside of boundaries", async function (){
            too_high_price = 100000000000
            too_low_price = 100
            negative_price = -1
            priceOracle.setPrice(too_high_price)
            const liquidity = ethers.utils.parseEther('1'); 

            await expect(depositReceipt.priceLiquidity(liquidity)).to.be.revertedWith("Upper price bound breached");
            priceOracle.setPrice(too_low_price)
            await expect(depositReceipt.priceLiquidity(liquidity)).to.be.revertedWith("Lower price bound breached");
            priceOracle.setPrice(negative_price)
            await expect(depositReceipt.priceLiquidity(liquidity)).to.be.revertedWith("Negative Oracle Price");
            
        });

        it.only("Should revert if Price update timestamp is stale", async function (){
            stale_timestamp = 1000000
            priceOracle.setTimestamp(stale_timestamp)
            const liquidity = ethers.utils.parseEther('1'); 

            await expect(depositReceipt.priceLiquidity(liquidity)).to.be.revertedWith("Stale pricefeed");
            
        });
      });
})
