# Oval Contracts
<p align="center">
  <img alt="UMA Logo" src="https://i.imgur.com/fSkkK5M.png" width="440">
</p>

Oval is an MEV capture mechanism that lets protocols reclaim Oracle Extractable Value(OEV) by auctioning oracle updates. It leveraged Flashbot's [MEV-share](https://docs.flashbots.net/flashbots-protect/mev-share) OFA system by running auctions for the right to backrun an oracle update.

For more information on how Oval works and how to integrate with it see the [docs](https://docs.oval.xyz/).

## Repo contents

This repository contains the main smart contracts for Oval Oracle. It uses [Foundry](https://github.com/foundry-rs/foundry). For spesific information on contracts, see the [Contract Architecture](https://app.gitbook.com/o/MZ06Z7ucpJtTO46hUUQr/s/tXEHwUXJ0YQakWqJOaw2/contract-architecture) section of the docs.

This repo also consists of a set of scripts used to profile the Oval gas usage. See [README](./scripts/README.md) that shows how to run these and [this](https://docs.oval.xyz/contract-architecture/gas-profiling) docs page that outlines the gas profiling finding.

### Building Contracts

```
forge build
```

### Running tests

This repository uses foundry fork tests. You will need to run the fork tests as follows:

```
export RPC_MAINNET=[your ethereum mainnet archive node url]
forge test
```
