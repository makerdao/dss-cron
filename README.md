# dss-cron

Keeper jobs for Maker protocol. Designed to support multiple Keeper Networks. All jobs will be deployed contracts which implement the `IJob` interface.

Keeper Networks will be required to register instances of these `IJob` contracts and call `getNextJob(networkName)` to get the next available action to execute (if any). Funding of keeper networks is a separate task.

# Deployed Contracts

Sequencer: [0xa0391743B97AaF8ce2662CeC316902D76c710dD3](https://etherscan.io/address/0xa0391743b97aaf8ce2662cec316902d76c710dd3#code)  
AutoLineJob: [0xd3E01B079f0a787Fc2143a43E2Bdd799b2f34d9a](https://etherscan.io/address/0xd3E01B079f0a787Fc2143a43E2Bdd799b2f34d9a#code)  
