const { expect } = require("chai")
const { ethers } = require("hardhat")
const { helpers } = require("../helpers/testHelpers.js")
const { addresses } = require("../helpers/deployedAddresses.js")
const { ABIs } = require("../helpers/abi.js")

describe.only("Integration OP Mainnet: DepositReceipt contract", function () {
    const provider = ethers.provider;
    const ADMIN_ROLE = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("ADMIN_ROLE"));
    const MINTER_ROLE = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("MINTER_ROLE"));

    const router_address = addresses.optimism.Router
    const USDC = addresses.optimism.USDC
    const sUSD = addresses.optimism.sUSD
    const price_feed_address = addresses.optimism.Chainlink_SUSD_Feed

    router = new ethers.Contract(router_address, ABIs.Router, provider)
    price_feed = new ethers.Contract(price_feed_address, ABIs.PriceFeed, provider)

    before(async function () {
        
        [owner, alice, bob, ...addrs] = await ethers.getSigners()
        DepositReceipt = await ethers.getContractFactory("DepositReceipt")
        

        depositReceipt = await DepositReceipt.deploy(
            "Deposit_Receipt",
            "DR",
            router.address,
            USDC,
            sUSD,
            true,
            price_feed.address
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
            const amount = ethers.utils.parseEther('353')
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
            const amount = ethers.utils.parseEther('353')
            const BASE = ethers.utils.parseEther('1')
            await depositReceipt.connect(bob).safeMint(amount)
            let nft_id = 1
            let new_nft_id = nft_id +1
            let split = ethers.utils.parseEther('0.53') //53%
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
            const amount = ethers.utils.parseEther('353')
            const BASE = ethers.utils.parseEther('1')
            await depositReceipt.connect(bob).safeMint(amount)
            let nft_id = 1
            let new_nft_id = nft_id +1
            let bad_split = ethers.utils.parseEther('1') //100%
            let bad_split_2 = ethers.utils.parseEther('2') //200%
        
            //call split here, check correct functioning
            await expect(depositReceipt.connect(owner).split(nft_id, bad_split)).to.be.revertedWith('split must be less than 100%')

            await expect(depositReceipt.connect(owner).split(nft_id, bad_split_2)).to.be.revertedWith('split must be less than 100%')

        });
      });

      describe("Pricing Pooled Tokens", function (){
        

        it("Should quote removable liquidity correctly", async function (){
            //pass through function so this only checks inputs haven't been mismatched
            const liquidity = ethers.utils.parseEther('1') 
            
            let output = await depositReceipt.viewQuoteRemoveLiquidity(liquidity)
            //error here
            let expected_output = await router.quoteRemoveLiquidity(USDC, sUSD, true, liquidity)
    
            expect(output[0]).to.equal(expected_output[0])
            expect(output[1]).to.equal(expected_output[1])
            

        });

        it("Should price liquidity right depending on which token USDC is", async function (){
            const liquidity = ethers.utils.parseEther('1')
            const ORACLE_BASE = 10 ** 8
            const SCALE_SHIFT = ethers.utils.parseEther('0.000001'); //1e12 used to scale USDC up
            let value = await depositReceipt.priceLiquidity(liquidity)
            
            //as token0 is not USDC we have assumed token1 is
            let outputs = await depositReceipt.viewQuoteRemoveLiquidity(liquidity)
            //as token0 is USDC we just scale up
            let value_token0 = outputs[0].mul(SCALE_SHIFT)
            let latest_round = await (price_feed.latestRoundData())
            let price = latest_round[1]
            let value_token1 = outputs[1].mul(price).div(ORACLE_BASE)
            let expected_value = ( value_token0 ).add( value_token1 )
            expect(value).to.equal(expected_value)



            //in the second instance USDC is token1

            depositReceipt2 = await DepositReceipt.deploy(
                "Deposit_Receipt2",
                "DR2",
                router.address,
                sUSD,
                USDC,
                true,
                price_feed.address
                )

                
            value = await depositReceipt2.priceLiquidity(liquidity)
            
            outputs = await depositReceipt.viewQuoteRemoveLiquidity(liquidity)
            //as token0 is not USDC we have assumed token1 is
            latest_round = await (price_feed.latestRoundData())
            price = latest_round[1]
            value_token0 = outputs[1].mul(price).div(ORACLE_BASE)
            
            //as token1 is USDC
            value_token1 = outputs[0].mul(SCALE_SHIFT)
            expected_value = ( value_token0 ).add( value_token1 )
            expect(value).to.equal(expected_value)

            
        });
      });
})
