# 6 DAO
Sample contract

Involved contracts:
- [dao](https://rinkeby.etherscan.io/address/0x2DE699707fb75eE84F366ecD7Fe433A8257fA63d)
- [voting token](https://rinkeby.etherscan.io/token/0x08da338ec0947ac3f504abde37a7dbbc856a3ed1)

```shell
npx hardhat accounts
npx hardhat deposit
npx hardhat addProposal
npx hardhat vote
npx hardhat finish

npx hardhat run --network rinkeby scripts/deploy.ts
npx hardhat verify --network rinkeby DEPLOYED_CONTRACT_ADDRESS <arg>

npx hardhat test
npx hardhat coverage
npx hardhat size-contracts

npx hardhat help
npx hardhat node
npx hardhat compile
npx hardhat clean
```
