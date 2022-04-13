# dss-cron

Keeper jobs for Maker protocol. Designed to support multiple Keeper Networks. All jobs will be deployed contracts which implement the `IJob` interface.

Keeper Networks will be required to watch the `activeJobs` array in the `Sequencer` and find all instances of available jobs. Helper methods `getNextJobs(...)` can be used to check a subsection (or everything) of the array all at once. Each job is safe to be executed in parallel.

Funding of keeper networks is a separate task.

# Deployed Contracts

Sequencer: [0x9566eB72e47E3E20643C0b1dfbEe04Da5c7E4732](https://etherscan.io/address/0x9566eB72e47E3E20643C0b1dfbEe04Da5c7E4732#code)  

## Active Jobs

AutoLineJob [thi=1000 bps, tlo=5000 bps]: [0x8099D3E7B6f63040FBd25c7B1541b34055e95e19](https://etherscan.io/address/0x8099D3E7B6f63040FBd25c7B1541b34055e95e19#code)  
LerpJob [maxDuration=1 day]: [0x6c254A698a4493226C47C8Fc79A1a6e4df68504b](https://etherscan.io/address/0x6c254A698a4493226C47C8Fc79A1a6e4df68504b#code)  
AaveDirectJob [threshold=50 bps]: [0x95416069ad8756f123Ad48fDB6fede7179b9Ecae](https://etherscan.io/address/0x95416069ad8756f123Ad48fDB6fede7179b9Ecae#code)  
ClipperMomJob: [0x81fAa76b5f7D6211AcBD43967387561e5A9803bD](https://etherscan.io/address/0x81fAa76b5f7D6211AcBD43967387561e5A9803bD#code)  
