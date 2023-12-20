<div align="center">
  <br />
  <br />
   <h1>Oval</h1>
  <br />
  <h3> Oval enables the redirection and capture of Oracle Extractable Value. </h3>
  <br />
</div>

Oval is designed as an enhancement over the standard oracles like Chainlink, wrapping around them to introduce a novel functionality: the unlocking of price updates. This unique feature allows Oval-enabled projects to capture _Oracle Extractable Value_(OEV), a form of value generated from oracle updates within a project. By disrupting the traditional MEV (Miner Extractable Value) supply chain, Oval opens up new revenue streams for projects. For instance, in a money market scenario, the protocol could earn revenue each time liquidations occur within its system. This is achieved by controlling the timing and accessibility of oracle updates, thus allowing the projects to strategically position themselves to benefit from the resulting market movements. This approach sets Oval apart, leveraging the reliability and familiarity of Chainlink's data while introducing a strategic layer for maximizing the value extracted from oracle updates.

For more information on how Oval works and how to integrate with it see [oval.docs.uma.xyz]().

# Repo contents

This repository contains the main smart contracts for Oval Oracle. It uses [foundry](https://github.com/foundry-rs/foundry).

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
