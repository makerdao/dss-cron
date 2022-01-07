# dss-cron

Keeper jobs for Maker protocol. Designed to support multiple Keeper Networks. All jobs will be deployed contracts which implement the `IJob` interface.

Keeper Networks will be required to watch the `activeJobs` array in the `Sequencer` and find all instances of available jobs. Helper methods `getNextJobs(...)` can be used to check a subsection (or everything) of the array all at once. Each job is safe to be executed in parallel.

Funding of keeper networks is a separate task.

# New Deployed Contracts (TBA)

Sequencer: N/A  
AutoLineJob: N/A  

# Old Deployed Contracts

Sequencer: [0xa0391743B97AaF8ce2662CeC316902D76c710dD3](https://etherscan.io/address/0xa0391743b97aaf8ce2662cec316902d76c710dd3#code)  
AutoLineJob: [0xd3E01B079f0a787Fc2143a43E2Bdd799b2f34d9a](https://etherscan.io/address/0xd3E01B079f0a787Fc2143a43E2Bdd799b2f34d9a#code)  
