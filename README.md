<img align="right" width="150" height="150" top="100" src="./public/readme.jpg">

# rysk-hmm • [![tests](https://github.com/N0xMare/rysk-hmm/actions/workflows/ci.yml/badge.svg?label=tests)](https://github.com/refcell/rysk-hmm/actions/workflows/ci.yml) ![license](https://img.shields.io/github/license/refcell/rysk-hmm?label=license) ![solidity](https://img.shields.io/badge/solidity-^0.8.19-lightgrey)

### Usage

**Building & Testing**

Build the foundry project with `forge build`. Then you can run tests with `forge test`.

**Deployment & Verification**

Inside the [`utils/`](./utils/) directory are a few preconfigured scripts that can be used to deploy and verify contracts.

Scripts take inputs from the cli, using silent mode to hide any sensitive information.

_NOTE: These scripts are required to be _executable_ meaning they must be made executable by running `chmod +x ./utils/*`._


### Blueprint

```txt
lib
├─ forge-std — https://github.com/foundry-rs/forge-std
├─ solmate — https://github.com/transmissions11/solmate
scripts
├─ Deploy.s.sol — Example Contract Deployment Script
src
├─ Greeter — Example Contract
test
└─ Greeter.t — Example Contract Tests
```
