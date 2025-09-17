// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.30;

import {TickNav} from "../libraries/TickNav.sol";

interface IPoolEvents {
    event TokenListed(address token);

    event TokenUnlisted(address token);

    event Deposit(address indexed sender, address indexed token, uint256 rawAmount);

    event Swap(
        address indexed sender, address indexed tokenIn, address indexed tokenOut, uint256 rawIn, uint256 rawOut
    );

    event Finalized(uint128 rNew);

    event Paused();

    event Unpaused();

    event InitializedMu(uint128 mu);

    event FeeUpdated(uint256 fee);

    event TickSet(int32 indexed tick, uint128 m, TickNav.TickMode mode);

    event TickCleared(int32 indexed tick);

    event CurrentTickSet(int32 indexed tick);

    event TickCrossed(int32 fromTick, int32 toTick);

    event TickParams(int32 indexed tick, uint128 r, int128 k, uint128 s);

    event TickModeChanged(int32 indexed tick, TickNav.TickMode mode);

    event SetTokenDisabled(address indexed token, bool disabled);

    event MaxStepsUpdated(uint8 steps);

    event FeeCollected(address indexed token, address indexed to, uint256 rawAmount);

    event TickRUpdated(int32 indexed tick, uint128 r);

    event TickKUpdated(int32 indexed tick, int128 k);
}
