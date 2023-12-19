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
