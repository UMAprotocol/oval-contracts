# Oval scripts

This package contains scripts for gas profiling of Oval.

## Installation

```bash
yarn
```

## Build

Start with generating contract typings:

```bash
yarn generate-contract-types
```

Then compile the scripts:

```bash
yarn build
```

## Usage

Make sure to copy `.env.example` to `.env` and fill in the required values.

Run gas profiling:

```bash
yarn gas-profiling
```

The script will create Tenderly forks that have Note starting with `Generated: 0x...`. This is used by the script to
 identify the forks that it had created and delete them when creating the same type of simulation. If you are sharing
 Tenderly forks with other people, it is better to remove the `Generated: 0x...` Note from the fork through Tenderly
 UI.


# Coinbase API Price Scripts

The following describes the Coinbase API Price Scripts to fetch cryptocurrency prices from the Coinbase API and logs related messages and signatures.

## Prerequisites

Before running the scripts you need to create an .env file in the scripts directory of the project and add the following environment variables:

```
    COINBASE_API_KEY=your_api_key
    COINBASE_API_SECRET=your_api_secret
    COINBASE_API_PASSPHRASE=your_api_passphrase
```

## Installation

To set up the project, you need to install the necessary dependencies. You can do this by running the following command in your terminal:

```
    yarn install
``` 

## Running the Scripts

Once the installation is complete, you can start the scripts with the following command:

Fetch data from the Coinbase API and save it to a file:
```
    node ./src/fetchData.js
``` 
Read data from the file and send it to stdout:
```
    node ./src/readData.js
```

## Integrating Signatures and Messages

test/unit/CoinbaseOracle.sol uses the out `fetchData.js` and `readData.js` scripts to fetch data from the Coinbase API and push it the CoinbaseOracle smart contract. Make sure the .env file is set up correctly before running the forge test.