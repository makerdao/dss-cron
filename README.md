# dss-cron

Keeper jobs for Maker protocol. Designed to support multiple Keeper Networks. All jobs will be deployed contracts which implement the `IJob` interface.

Keeper Networks will be required to watch the `activeJobs` array in the `Sequencer` and find all instances of available jobs. Helper methods `getNextJobs(...)` can be used to check a subsection (or everything) of the array all at once. Each job is safe to be executed in parallel.

Funding of keeper networks is a separate task.

# Deployed Contracts

Sequencer: [0x9566eB72e47E3E20643C0b1dfbEe04Da5c7E4732](https://etherscan.io/address/0x9566eB72e47E3E20643C0b1dfbEe04Da5c7E4732#code)  

## Active Jobs

AutoLineJob [thi=1000 bps, tlo=5000 bps]: [0x8f235dD319ef8637964271a9477234f62B02Cb59](https://etherscan.io/address/0x8f235dD319ef8637964271a9477234f62B02Cb59#code)  
LerpJob [maxDuration=1 day]: [0x17cE6976de56FAf445956e5713b382C28F7A9390](https://etherscan.io/address/0x17cE6976de56FAf445956e5713b382C28F7A9390#code)  
AaveDirectJob [threshold=50 bps]: [0xc194673e6157Eca981dEDc1eEf49250aD8055D94](https://etherscan.io/address/0xc194673e6157Eca981dEDc1eEf49250aD8055D94#code)  
ClipperMomJob: [0x01d73bC5FD31AF6b01655bF29B8Ff2FF0d323F30](https://etherscan.io/address/0x01d73bC5FD31AF6b01655bF29B8Ff2FF0d323F30#code)  
