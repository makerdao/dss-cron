# dss-cron

Keeper jobs for Maker protocol. Designed to support multiple Keeper Networks. All jobs will be deployed contracts which implement the `IJob` interface.

Keeper Networks will be required to watch the `activeJobs` array in the `Sequencer` and find all instances of available jobs. Helper methods `getNextJobs(...)` can be used to check a subsection (or everything) of the array all at once. Each job is safe to be executed in parallel.

Funding of keeper networks is a separate task.

# Deployed Contracts

Sequencer: [0x9566eB72e47E3E20643C0b1dfbEe04Da5c7E4732](https://etherscan.io/address/0x9566eB72e47E3E20643C0b1dfbEe04Da5c7E4732#code)  
AutoLineJob [thi=1000,tlo=5000]: [0x8f235dD319ef8637964271a9477234f62B02Cb59](https://etherscan.io/address/0x8f235dD319ef8637964271a9477234f62B02Cb59#code)  
