// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.30;

interface IPoolErrors {
    error InvalidToken(address token);

    error SameToken(address token);

    error PoolInactive();

    error InvalidAmount(uint256 amount);

    error InvalidMu(uint128 value);

    error CannotSolveInvariant();

    error CrossesFloor();

    error InvalidFee(uint256 fee);

    error InvalidTick(int32 tick);

    error InvalidR(uint128 r);

    error DeadlineExceeded(uint256 deadline);

    error InsufficientLiquidity(uint256 available, uint256 required);

    error InvalidSteps(uint256 steps, uint256 minSteps, uint256 maxSteps);

    error BoundaryOff();

    error UnsupportedDirection();

    error MustPause();

    error PoolPaused();

    error PoolNotPaused();

    error PoolNotLocked();

    error PoolLocked();

    error NotEnoughTokens(uint256 n);

    error TokenAlreadyListed(address token);

    error ReserveOverflow(uint256 amount);

    error InvalidTo(address to);

    error NotImplemented();
}
