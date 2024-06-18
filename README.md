# Oval Contracts
<p align="center">
  <img alt="UMA Logo" src="https://i.imgur.com/fSkkK5M.png" width="440">
</p>

Oval is an MEV capture mechanism that lets protocols reclaim Oracle Extractable Value(OEV) by auctioning oracle updates. It leverages Flashbot's [MEV-share](https://docs.flashbots.net/flashbots-protect/mev-share) OFA system by running auctions for the right to backrun an oracle update.

For more information on how Oval works and how to integrate with it see the [docs](https://docs.oval.xyz/).

## Repo contents

This repository contains the main smart contracts for Oval. It uses [Foundry](https://github.com/foundry-rs/foundry). For specific information on contracts, see the [Contract Architecture](https://docs.oval.xyz/contract-architecture) section of the docs.

This repo also consists of a set of scripts used to profile the Oval gas usage. See [README](./scripts/README.md) that shows how to run these and [this](https://docs.oval.xyz/contract-architecture/gas-profiling) docs page that outlines the gas profiling finding.

### Installing Foundry

Tests in this repo work up to [Nightly (2024-03-02)](https://github.com/foundry-rs/foundry/releases/tag/nightly-de33b6af53005037b463318d2628b5cfcaf39916) Foundry version, so make sure to use it when installing:

```
foundryup -v nightly-de33b6af53005037b463318d2628b5cfcaf39916
```

### Building Contracts

```
forge build
```

### Running tests

This repository uses foundry fork tests. You will need to run the fork tests as follows:

```
export RPC_MAINNET=[your Ethereum mainnet archive node url]
forge test
```

## License

All code in this repository is licensed under BUSL-1.1 unless specified differently in the file. Individual exceptions to this license can be made by Risk Labs, which holds the rights to this software and design. If you are interested in using the code or designs in a derivative work, feel free to reach out to licensing@risklabs.foundation.
