# Orbital

An AMM with concentrated liquidity for pools of 2, 3, or 10,000 stablecoins, based on [Paradigm’s Orbital paper](https://www.paradigm.xyz/2025/06/orbital).

## Status

**Are we orbital yet?**\
No. But our north star is to get there.

### What's built:

-   O(1) bookkeeping
-   Closed-form within-segment quote/simulation
-   Virtual reserves & floors
-   Boundary math
-   Tick guard for downward crossings

### What needs to be built:

-   Visualization of the entire paper _(I'm working on this rn and should be out soon)_
-   Full multi-tick traversal
-   Explicit consolidation state
-   Global torus-invariant solver
-   More tests (also fuzz tests)
-   Gas profiling & optimizations (haven't really optimized anything yet)

## Design

### External Libraries

-   `forge-std`
-   `Solday`

### Interfaces

-   `IPoolMetadata.sol` - Holds `TokenConfig` struct and signatures for view functions.
-   `IPoolEvents.sol` - Holds events that will be emitted by the Pool.
-   `IPoolErrors.sol` - Holds errors used by the Pool.
-   `IPool.sol` - Extends the previous 3 interfaces and holds function signatures for non-view functions.

### Libraries

-   `WadScale.sol` - Handles scaling to and from WAD.
-   `TickBitmap.sol` - Handles storing and traversing of ticks in a bitmap. Based on `LibBit` from Solday.
-   `TickNav.sol` - Exposes higher level functions to traverse through ticks.
-   `OrbitalMath.sol` - Core math: closed-form segment quotes, invariant updates, and tick guards.

### Contracts

-   `PoolStorage.sol` - Abstract contract that holds state variables for the Pool.
-   `Pool.sol` - Core Pool smart contract that extends `IPool` and `PoolStorage`.

## Quick Start

### Prerequisites
- [Foundry](https://getfoundry.sh/) installed

### Installation
```bash
git clone https://github.com/aadeexyz/orbital.git
cd orbital
forge install
```

### Build & Test
```bash
forge test
```

## Tests
> [!WARNING] 
> Tests are AI generated and may have errors. Pwease hewp me with the tests UwU.

| File | Tests | Passing |
| - | - | -|
| WadScale.t.sol | 9 | ✅ |
| TickBitmap.t.sol | 12 | ✅ |
| TickNav.t.sol | 7 | ✅ |
| OrbitalMath.t.sol | 14 | ✅ |
| Pool.t.sol | 17 | ✅ |

## Contributing
Please contribute cause I can't build it alone TwT

### Development Workflow
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Make sure you are using Solidity version ^0.8.30
6. Ensure all tests pass (you can modify existing tests if they feel wrong over time)
7. Submit a pull request
8. Make sure the pull request details what you've added

### Code Standards
- Follow Solidity style guide
- Please don't dump everything in the same file

## Security
This software is experimental and unaudited, and is provided on an 'as is' and 'as available' basis. We do not give any warranties and will not be liable for any loss incurred through any use of this codebase.


## License
This project is licensed under the Apache-2.0 License - see the [LICENSE](LICENSE) file for details.