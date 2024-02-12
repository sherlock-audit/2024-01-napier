import * as dotenv from 'dotenv'

import '@nomicfoundation/hardhat-toolbox'
import { HardhatUserConfig } from 'hardhat/types'
// it will be able to use dependencies installed with forge install
import '@nomicfoundation/hardhat-foundry'
import "hardhat-contract-sizer"

dotenv.config()

const DEFAULT_OPTIMIZER_COMPILER_SETTINGS = {
  version: '0.8.19',
  settings: {
    evmVersion: 'paris',
    optimizer: {
      enabled: true,
      runs: 10_000,
    },
    metadata: {
      bytecodeHash: 'none',
    },
  },
}

const LOW_OPTIMIZER_COMPILER_SETTINGS = {
  version: '0.8.19',
  settings: {
    evmVersion: 'paris',
    optimizer: {
      enabled: true,
      runs: 500,
    },
    metadata: {
      bytecodeHash: 'none',
    },
  },
}

const LOWEST_OPTIMIZER_COMPILER_SETTINGS = {
  version: '0.8.19',
  settings: {
    evmVersion: 'paris',
    optimizer: {
      enabled: true,
      runs: 1,
    },
    metadata: {
      bytecodeHash: 'none',
    },
  },
}
const MEDIUM_OPTIMIZER_COMPILER_SETTINGS = {
  version: '0.8.19',
  settings: {
    evmVersion: 'paris',
    optimizer: {
      enabled: true,
      runs: 5_000,
    },
    metadata: {
      bytecodeHash: 'none',
    },
  },
}

const HIGH_OPTIMIZER_COMPILER_SETTINGS = {
  version: '0.8.19',
  settings: {
    evmVersion: 'paris',
    optimizer: {
      enabled: true,
      runs: 100_000,
    },
    metadata: {
      bytecodeHash: 'none',
    },
  },
}

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      DEFAULT_OPTIMIZER_COMPILER_SETTINGS
    ],
    overrides: {
      "src/NapierRouter.sol": HIGH_OPTIMIZER_COMPILER_SETTINGS,
      "src/NapierPool.sol": MEDIUM_OPTIMIZER_COMPILER_SETTINGS,
      "src/PoolFactory.sol": LOW_OPTIMIZER_COMPILER_SETTINGS,
      "src/libs/Create2PoolLib.sol": LOW_OPTIMIZER_COMPILER_SETTINGS,
      "src/lens/Quoter.sol": LOWEST_OPTIMIZER_COMPILER_SETTINGS
    },
  },
  networks: {
    hardhat: {
      blockGasLimit: 30_000_000,
    },
    sepolia: {
      url: process.env.SEPOLIA_RPC_URL,
      accounts: [process.env.PK as string],
    }
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
  // Avoid foundry cache conflict.
  paths: {
    sources: 'src', // Use ./src rather than ./contracts as Hardhat expects
    cache: 'hh-cache',
  },
}

export default config
