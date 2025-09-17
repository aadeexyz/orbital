// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.30;

import {IPoolEvents} from "./IPoolEvents.sol";
import {IPoolErrors} from "./IPoolErrors.sol";
import {IPoolMetadata} from "./IPoolMetadata.sol";
import {TickNav} from "../libraries/TickNav.sol";

interface IPool is IPoolEvents, IPoolErrors, IPoolMetadata {
    function setFee(uint256 fee_) external;

    function setMaxSteps(uint8 steps_) external;

    function setTokenDisabled(address token_, bool disabled_) external;

    function pause() external;

    function unpause() external;

    function setCurrentTick(int32 tick_) external;

    function setTickRK(int32 tick_, uint128 m_, uint128 r_, int128 k_, TickNav.TickMode mode_) external;

    function updateTickR(int32 tick_, uint128 newR_) external;

    function updateTickK(int32 tick_, int128 newK_) external;

    function setTickMode(int32 tick_, TickNav.TickMode newMode_) external;

    function recomputeAllTickSums() external;

    function finalize() external;

    function listToken(address token_, uint256 rawAmount_) external;

    // function unlistToken(address token_) external;

    function deposit(address token_, uint256 rawAmount_) external;

    function swapExactIn(
        address tokenIn_,
        address tokenOut_,
        uint256 amountIn_,
        uint256 minimumAmountOut_,
        address to_,
        uint256 deadline_
    ) external returns (uint256, uint256);

    function swapExactOut(
        address tokenIn_,
        address tokenOut_,
        uint256 amountOut_,
        uint256 maximumAmountIn_,
        address to_,
        uint256 deadline_
    ) external returns (uint256, uint256);
}
