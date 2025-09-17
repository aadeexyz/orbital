// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.30;

interface IPoolMetadata {
    struct TokenConfig {
        uint128 reserve;
        uint64 factor;
        uint8 decimals;
        bool scaleUp;
        bool disabled;
        bool supported;
    }

    function currentTick() external view returns (int32);

    function ticksEnabled() external view returns (bool);
}
