// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.30;

import {IPool} from "./interfaces/IPool.sol";
import {TickNav} from "./libraries/TickNav.sol";
import {TickBitmap} from "./libraries/TickBitmap.sol";
import {OrbitalMath} from "./libraries/OrbitalMath.sol";

abstract contract PoolStorage is IPool {
    uint128 public immutable MU;
    uint256 public immutable MU_SQ;

    uint128 internal _r;
    uint16 internal _n;

    uint8 internal _maxSteps = 12;
    bool internal _boundaryEnabled = false;

    uint16 internal _countBelow;
    uint256 internal _sumBelow;
    uint256 internal _sumSqBelow;

    int32 internal _currentTick;
    bool internal _ticksEnabled;

    uint256 internal _tickLowerBound;
    bool internal _currentTickInitialized;

    mapping(int32 => TickNav.Tick) internal _ticks;
    TickBitmap.Bitmap internal _tickmap;

    mapping(address => TokenConfig) internal _tokenConfig;

    uint256 internal _sumRes;
    uint256 internal _sumSq;

    uint256 internal _fee;
    uint256 internal _globalFeeGrowth;
    mapping(address => uint256) internal _feeAccrued;

    uint256 internal _rInterior;
    uint256 internal _rBoundary;
    uint256 internal _sBoundary;
    int256 internal _kBoundary;

    uint256 internal _inverseSqrtN;

    bool internal _paused;
    bool internal _locked;

    constructor(uint128 mu_) {
        if (mu_ <= 0) {
            revert InvalidMu(mu_);
        }

        MU = mu_;
        MU_SQ = OrbitalMath.squareWad(mu_);

        emit InitializedMu(mu_);
    }
}
