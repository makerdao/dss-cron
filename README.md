# dss-cron

Keeper jobs for Maker protocol. Designed to support multiple Keeper Networks. All jobs will be deployed contracts which implement the `IJob` interface.

Keeper Networks will be required to register instances of these `IJob` contracts and call `getNextJob(networkName)` to get the next available action to execute (if any). Funding of keeper networks is a separate task.
