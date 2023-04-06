# dss-cron

Keeper jobs for Maker protocol. Designed to support multiple Keeper Networks. All jobs will be deployed contracts which implement the `IJob` interface.

Keeper Networks will be required to watch the `activeJobs` array in the `Sequencer` and find all instances of available jobs. Helper methods `getNextJobs(...)` can be used to check a subsection (or everything) of the array all at once. Each job is safe to be executed in parallel.

Funding of keeper networks is done through `dss-vest`.

It is important that the `work` function succeeds IF AND ONLY IF the `workable` function returns a valid execution. It is tempting to save gas by allowing execution if the internal function itself passes, but this opens an attack vector where keeper networks can spam the function to collect the DAI payout. Furthermore, care should be taken to ensure keeper networks cannot mess with the state to produce valid job executions in rapid succession as this opens up a spam attack vector too. If jobs are susceptable to this they should include a cooldown period to prevent these types of spam.

# Deployed Contracts

Sequencer: [0x238b4E35dAed6100C6162fAE4510261f88996EC9](https://etherscan.io/address/0x238b4E35dAed6100C6162fAE4510261f88996EC9#code)  

## Active Jobs

AutoLineJob [thi=1000 bps, tlo=5000 bps]: [0x67AD4000e73579B9725eE3A149F85C4Af0A61361](https://etherscan.io/address/0x67AD4000e73579B9725eE3A149F85C4Af0A61361#code)  
LerpJob [maxDuration=1 day]: [0x8F8f2FC1F0380B9Ff4fE5c3142d0811aC89E32fB](https://etherscan.io/address/0x8F8f2FC1F0380B9Ff4fE5c3142d0811aC89E32fB#code)  
D3MJob [threshold=500 bps, ttl=10 minutes]: [0x1Bb799509b0B039345f910dfFb71eEfAc7022323](https://etherscan.io/address/0x1Bb799509b0B039345f910dfFb71eEfAc7022323#code)  
ClipperMomJob: [0xc3A76B34CFBdA7A3a5215629a0B937CBDEC7C71a](https://etherscan.io/address/0xc3A76B34CFBdA7A3a5215629a0B937CBDEC7C71a#code)  
OracleJob: [0x00815d78D8FafCc9d61784c9b6Ce3b55d40e4950](https://etherscan.io/address/0x00815d78D8FafCc9d61784c9b6Ce3b55d40e4950#code)  

## Network Payment Adapters

NetworkPaymentAdapter (Gelato): [0x0B5a34D084b6A5ae4361de033d1e6255623b41eD](https://etherscan.io/address/0x0B5a34D084b6A5ae4361de033d1e6255623b41eD#code)  
NetworkPaymentAdapter (Keep3r Network): [0xaeFed819b6657B3960A8515863abe0529Dfc444A](https://etherscan.io/address/0xaeFed819b6657B3960A8515863abe0529Dfc444A#code)  
NetworkPaymentAdapter (Chainlink): [0xfB5e1D841BDA584Af789bDFABe3c6419140EC065](https://etherscan.io/address/0xfB5e1D841BDA584Af789bDFABe3c6419140EC065#code)  
