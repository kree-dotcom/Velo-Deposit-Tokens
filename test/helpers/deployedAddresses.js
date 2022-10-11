
//optimism mainnet addresses
const sUSD = `0x8c6f28f2F1A3C87F0f938b96d27520d9751ec8d9`
const USDC = "0x7F5c764cBc14f9669B88837ca1490cCa17c31607" 
const VELO = "0x3c8B650257cFb5f272f799F5e2b4e65093a11a05"
const sAMM_USDC_sUSD = "0xd16232ad60188B68076a235c65d692090caba155"
const gauge = "0xb03f52D2DB3e758DD49982Defd6AeEFEa9454e80"
const voter = "0x09236cfF45047DBee6B921e00704bed6D6B8Cf7e"
const router = "0xa132DAB612dB5cB9fC9Ac426A0Cc215A3423F9c9"
const chainlink_SUSD_feed = "0x7f99817d87baD03ea21E05112Ca799d715730efe"

const sAMM_USDC_sUSD_donor = "0x0E4375cA948a0Cc301dd0425A4c5e163b03a65D0"



const optimism_OP = {sUSD: sUSD, 
                     USDC: USDC,
                     VELO: VELO,
                     AMMToken : sAMM_USDC_sUSD,
                     Gauge : gauge,
                     Voter : voter,
                     Router : router,
                     AMMToken_Donor : sAMM_USDC_sUSD_donor,
                     Chainlink_SUSD_Feed : chainlink_SUSD_feed}


addresses = {optimism: optimism_OP}

module.exports = { addresses }


      
      
      