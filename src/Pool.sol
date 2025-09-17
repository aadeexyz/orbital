// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.30;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {IPool} from "./interfaces/IPool.sol";
import {PoolStorage} from "./PoolStorage.sol";
import {TickNav} from "./libraries/TickNav.sol";
import {TickBitmap} from "./libraries/TickBitmap.sol";
import {OrbitalMath} from "./libraries/OrbitalMath.sol";
import {WadScale} from "./libraries/WadScale.sol";

contract Pool is IPool, PoolStorage, ReentrancyGuard, Ownable {
    using SafeTransferLib for address;
    using TickBitmap for TickBitmap.Bitmap;

    modifier whenPaused() {
        if (!_paused) {
            revert PoolNotPaused();
        }
        _;
    }

    modifier whenNotPaused() {
        if (_paused) {
            revert PoolPaused();
        }
        _;
    }

    modifier whenLocked() {
        if (!_locked) {
            revert PoolNotLocked();
        }
        _;
    }

    modifier whenNotLocked() {
        if (_locked) {
            revert PoolLocked();
        }
        _;
    }

    modifier boundaryEnabled() {
        if (!_boundaryEnabled) {
            revert BoundaryOff();
        }
        _;
    }

    constructor(uint128 mu_, uint256 fee_, address owner_) PoolStorage(mu_) {
        _setFee(fee_);
        _initializeOwner(owner_);
    }

    function setFee(uint256 fee_) external onlyOwner {
        _setFee(fee_);
    }

    function setMaxSteps(uint8 steps_) external onlyOwner {
        if (steps_ < 1 || steps_ > 100) {
            revert InvalidSteps(steps_, 1, 100);
        }
        _maxSteps = steps_;
        emit MaxStepsUpdated(steps_);
    }

    function setTokenDisabled(address token_, bool disabled_) external onlyOwner {
        TokenConfig storage config = _tokenConfig[token_];
        if (!config.supported) {
            revert InvalidToken(token_);
        }

        config.disabled = disabled_;
        emit SetTokenDisabled(token_, disabled_);
    }

    function pause() external onlyOwner whenNotPaused {
        _paused = true;
        emit Paused();
    }

    function unpause() external onlyOwner whenPaused {
        _paused = false;
        emit Unpaused();
    }

    function setCurrentTick(int32 tick_) external onlyOwner {
        if (!_ticks[tick_].set) {
            revert InvalidTick(tick_);
        }
        _currentTick = tick_;
        emit CurrentTickSet(tick_);
    }

    function setTickRK(int32 tick_, uint128 m_, uint128 r_, int128 k_, TickNav.TickMode mode_)
        external
        onlyOwner
        whenPaused
        boundaryEnabled
    {
        if (r_ <= 0) {
            revert InvalidR(r_);
        }
        _setTickRK(tick_, m_, r_, k_, mode_);
    }

    function updateTickR(int32 tick_, uint128 newR_) external onlyOwner whenPaused boundaryEnabled {
        TickNav.Tick storage tick = _ticks[tick_];
        if (!tick.set) {
            revert InvalidTick(tick_);
        }

        _removeTickFromAggregates(tick_);
        tick.r = newR_;
        tick.s = OrbitalMath.computeSBoundary(newR_, tick.k, _inverseSqrtN);
        _addTickToAggregates(tick_);

        emit TickParams(tick_, tick.r, tick.k, tick.s);
        emit TickRUpdated(tick_, newR_);
    }

    function updateTickK(int32 tick_, int128 newK_) external onlyOwner whenPaused boundaryEnabled {
        TickNav.Tick storage tick = _ticks[tick_];
        if (!tick.set) {
            revert InvalidTick(tick_);
        }

        _removeTickFromAggregates(tick_);
        tick.k = newK_;
        tick.s = OrbitalMath.computeSBoundary(tick.r, newK_, _inverseSqrtN);
        _addTickToAggregates(tick_);

        emit TickParams(tick_, tick.r, tick.k, tick.s);
        emit TickKUpdated(tick_, newK_);
    }

    function setTickMode(int32 tick_, TickNav.TickMode newMode_) external onlyOwner whenPaused {
        TickNav.Tick storage tick = _ticks[tick_];
        if (!tick.set) {
            revert InvalidTick(tick_);
        }
        if (tick.mode == newMode_) {
            return;
        }

        _removeTickFromAggregates(tick_);
        tick.mode = newMode_;
        _addTickToAggregates(tick_);

        emit TickModeChanged(tick_, newMode_);
    }

    function recomputeAllTickSums() external whenPaused onlyOwner {
        _rInterior = 0;
        _rBoundary = 0;
        _sBoundary = 0;
        _kBoundary = 0;

        if (!_ticksEnabled) {
            return;
        }

        uint256 indexMax = type(uint32).max;
        uint256 index = _tickmap.nextSet(_tickLowerBound, indexMax);
        while (index != TickBitmap.NOT_FOUND) {
            int32 t = TickNav.fromIndex(index);
            TickNav.Tick storage tick = _ticks[t];
            if (tick.set) {
                tick.s = OrbitalMath.computeSBoundary(tick.r, tick.k, _inverseSqrtN);
                _addTickToAggregates(t);
            }
            if (index == indexMax) {
                break;
            }
            index = _tickmap.nextSet(index + 1, indexMax);
        }
    }

    function finalize() external whenNotLocked onlyOwner {
        if (_n < 2) {
            revert NotEnoughTokens(_n);
        }
        (uint256 sEffective, uint256 qEffective) = OrbitalMath.effectiveSums(_sumRes, _sumSq, _n, _activeM());
        uint256 a = uint256(_n) - 1;
        uint256 disc = sEffective * sEffective - a * FixedPointMathLib.WAD * qEffective;
        uint256 sqrtTerm = FixedPointMathLib.sqrt(disc);
        uint256 rNew = (sEffective + sqrtTerm) / a;
        _r = uint128(rNew);
        _locked = true;
        emit Finalized(uint128(rNew));
    }

    function listToken(address token_, uint256 rawAmount_) external onlyOwner nonReentrant whenNotLocked whenPaused {
        TokenConfig storage config = _tokenConfig[token_];
        if (config.supported) {
            revert TokenAlreadyListed(token_);
        }
        if (rawAmount_ == 0) {
            revert InvalidAmount(rawAmount_);
        }

        uint8 decimals = IERC20(token_).decimals();
        if (decimals > 24) {
            revert InvalidToken(token_);
        }

        (bool scaleUp, uint64 factor) = WadScale.computeScale64(decimals);

        token_.safeTransferFrom(msg.sender, address(this), rawAmount_);
        uint256 wad = WadScale.toWad(rawAmount_, scaleUp, factor);
        if (wad == 0) {
            revert InvalidAmount(rawAmount_);
        }

        config.supported = true;
        config.decimals = decimals;
        config.disabled = false;
        config.scaleUp = scaleUp;
        config.factor = factor;
        config.reserve = uint128(wad);

        unchecked {
            ++_n;
        }

        _updateInverseSqrtN();

        _sumRes += wad;
        _sumSq += OrbitalMath.squareWad(wad);

        if (MU != 0 && wad < MU) {
            unchecked {
                ++_countBelow;
                _sumBelow += wad;
                _sumSqBelow += OrbitalMath.squareWad(wad);
            }
        }
        emit TokenListed(token_);
    }

    function deposit(address token_, uint256 rawAmount_) external nonReentrant {
        TokenConfig storage config = _tokenConfig[token_];
        if (!config.supported || config.disabled) {
            revert InvalidToken(token_);
        }
        if (rawAmount_ == 0) {
            revert InvalidAmount(rawAmount_);
        }

        token_.safeTransferFrom(msg.sender, address(this), rawAmount_);

        uint256 addRes = WadScale.toWad(rawAmount_, config.scaleUp, config.factor);
        if (addRes == 0) {
            revert InvalidAmount(rawAmount_);
        }

        uint256 oldVal = config.reserve;
        uint256 newVal = oldVal + addRes;
        if (newVal > type(uint128).max) {
            revert ReserveOverflow(newVal);
        }

        if (MU != 0 && oldVal < MU) {
            if (newVal < MU) {
                _sumBelow += addRes;
                _sumSqBelow += OrbitalMath.squareWad(newVal) - OrbitalMath.squareWad(oldVal);
            } else {
                unchecked {
                    --_countBelow;
                }
                _sumBelow -= oldVal;
                _sumSqBelow -= OrbitalMath.squareWad(oldVal);
            }
        }

        config.reserve = uint128(newVal);
        _sumRes += addRes;
        _sumSq = _sumSq - OrbitalMath.squareWad(oldVal) + OrbitalMath.squareWad(newVal);

        emit Deposit(msg.sender, token_, rawAmount_);
    }

    function swapExactIn(
        address tokenIn_,
        address tokenOut_,
        uint256 amountIn_,
        uint256 minimumAmountOut_,
        address to_,
        uint256 deadline_
    ) external nonReentrant whenLocked whenNotPaused returns (uint256, uint256) {
        if (tokenIn_ == address(0) || tokenOut_ == address(0)) {
            revert InvalidToken(address(0));
        }
        if (tokenIn_ == tokenOut_) {
            revert SameToken(tokenIn_);
        }
        if (amountIn_ == 0) {
            revert InvalidAmount(amountIn_);
        }
        if (to_ == address(0)) {
            revert InvalidTo(to_);
        }
        if (block.timestamp > deadline_) {
            revert DeadlineExceeded(deadline_);
        }

        (uint256 amountOut, uint256 amountInUsed) = _swapExactIn(tokenIn_, tokenOut_, amountIn_, minimumAmountOut_, to_);

        emit Swap(msg.sender, tokenIn_, tokenOut_, amountInUsed, minimumAmountOut_);

        return (amountOut, amountInUsed);
    }

    function swapExactOut(
        address tokenIn_,
        address tokenOut_,
        uint256 amountOut_,
        uint256 maximumAmountIn_,
        address to_,
        uint256 deadline_
    ) external nonReentrant whenLocked whenNotPaused returns (uint256, uint256) {
        if (tokenIn_ == address(0) || tokenOut_ == address(0)) {
            revert InvalidToken(address(0));
        }
        if (tokenIn_ == tokenOut_) {
            revert SameToken(tokenIn_);
        }
        if (maximumAmountIn_ == 0) {
            revert InvalidAmount(amountOut_);
        }
        if (to_ == address(0)) {
            revert InvalidTo(to_);
        }
        if (block.timestamp > deadline_) {
            revert DeadlineExceeded(deadline_);
        }

        _swapExactOut(tokenIn_, tokenOut_, amountOut_, maximumAmountIn_, to_);
    }

    function currentTick() external view returns (int32) {
        return _currentTick;
    }

    function ticksEnabled() external view returns (bool) {
        return _ticksEnabled;
    }

    function _setFee(uint256 fee_) private {
        // allowing upto 1% fee
        if (fee_ > 1e16) {
            revert InvalidFee(fee_);
        }
        _fee = fee_;
        emit FeeUpdated(fee_);
    }

    function _setTickRK(int32 tick_, uint128 m_, uint128 r_, int128 k_, TickNav.TickMode mode_) private {
        TickNav.Tick storage tick = _ticks[tick_];

        if (tick.set) {
            _removeTickFromAggregates(tick_);
        }

        tick.m = m_;
        tick.mode = mode_;
        tick.set = true;
        tick.r = r_;
        tick.k = k_;
        tick.s = OrbitalMath.computeSBoundary(r_, k_, _inverseSqrtN);

        uint256 index = TickNav.toIndex(tick_);
        _tickmap.set(index);

        if (!_ticksEnabled) {
            _ticksEnabled = true;
            _tickLowerBound = index;
            _currentTick = tick_;
            _currentTickInitialized = true;

            emit CurrentTickSet(tick_);
        } else if (index < _tickLowerBound) {
            _tickLowerBound = index;
        }

        if (r_ > 0) {
            _addTickToAggregates(tick_);
        }

        emit TickSet(tick_, m_, mode_);
        emit TickParams(tick_, r_, k_, tick.s);
    }

    function _addTickToAggregates(int32 tick_) private {
        TickNav.Tick storage tick = _ticks[tick_];
        if (tick.r == 0) return;
        if (tick.mode == TickNav.TickMode.Boundary) {
            _rBoundary += tick.r;
            _sBoundary += tick.s;
            _kBoundary += int256(tick.k);

            return;
        }
        _rInterior += tick.r;
    }

    function _removeTickFromAggregates(int32 tick_) private {
        TickNav.Tick storage tick = _ticks[tick_];

        if (tick.r == 0) return;

        if (tick.mode == TickNav.TickMode.Boundary) {
            _rBoundary -= tick.r;
            _sBoundary -= tick.s;
            _kBoundary -= int256(tick.k);
        } else if (tick.mode == TickNav.TickMode.Interior) {
            _rInterior -= tick.r;
        }
    }

    function _activeM() private view returns (uint256) {
        if (!_ticksEnabled) return 0;
        TickNav.Tick storage tick = _ticks[_currentTick];
        return tick.set ? tick.m : 0;
    }

    function _updateInverseSqrtN() private {
        if (_n == 0) {
            _inverseSqrtN = 0;
            return;
        }
        uint256 sqrtN = FixedPointMathLib.sqrt(uint256(_n));
        _inverseSqrtN = sqrtN == 0 ? 0 : (FixedPointMathLib.WAD / sqrtN);
    }

    function _applySegmentAccounting(
        address tokenIn_,
        TokenConfig memory tokenInConfig_,
        uint256 xInOld_,
        uint256 dxRaw_,
        uint256 fee_,
        uint256 mu_
    ) private returns (uint256, uint256, uint256, uint256) {
        (bool ok, uint256 dx) = WadScale.toWadSafe(dxRaw_, tokenInConfig_.scaleUp, tokenInConfig_.factor);
        if (!ok || dx == 0) {
            return (0, 0, 0, xInOld_);
        }

        uint256 fee = FixedPointMathLib.mulWad(dx, fee_);
        uint256 dxNet = dx - fee;
        uint256 xInNewSolve = xInOld_ + dxNet;

        if (mu_ != 0 && xInOld_ < mu_) {
            if (xInNewSolve < mu_) {
                _sumBelow += dxNet;
                _sumSqBelow += OrbitalMath.squareWad(xInNewSolve) - OrbitalMath.squareWad(xInOld_);
            } else {
                unchecked {
                    --_countBelow;
                }
                _sumBelow -= xInOld_;
                _sumSqBelow -= OrbitalMath.squareWad(xInOld_);
            }
        }

        if (fee != 0) {
            _feeAccrued[tokenIn_] += fee;
            _globalFeeGrowth += fee;
        }

        return (dx, fee, dxNet, xInNewSolve);
    }

    function _swapExactIn(address tokenIn_, address tokenOut_, uint256 rawDxCap_, uint256 minDy_, address to_)
        private
        returns (uint256, uint256)
    {
        TokenConfig storage tokenInConfig = _tokenConfig[tokenIn_];
        TokenConfig storage tokenOutConfig = _tokenConfig[tokenOut_];

        if (!tokenInConfig.supported || tokenInConfig.disabled) {
            revert InvalidToken(tokenIn_);
        }
        if (!tokenOutConfig.supported || tokenOutConfig.disabled) {
            revert InvalidToken(tokenOut_);
        }
        if (rawDxCap_ == 0) {
            revert InvalidAmount(rawDxCap_);
        }

        tokenIn_.safeTransferFrom(msg.sender, address(this), rawDxCap_);

        uint256 xIn = tokenInConfig.reserve;
        uint256 xOut = tokenOutConfig.reserve;
        uint256 s = _sumRes;
        uint256 q = _sumSq;

        int32 tick = _currentTick;
        uint8 steps = 0;

        uint256 rawDxUsed = 0;
        uint256 rawDyOut = 0;
        uint256 remaining = rawDxCap_;
        while (remaining != 0) {
            unchecked {
                steps++;
            }
            if (steps > _maxSteps) {
                revert InvalidSteps(steps, 1, _maxSteps);
            }

            uint256 m = (_ticksEnabled && _ticks[tick].set) ? _ticks[tick].m : 0;

            OrbitalMath.QuoteContext memory qctx = OrbitalMath.QuoteContext({
                tokenInConfig: tokenInConfig,
                tokenOutConfig: tokenOutConfig,
                xInOld: xIn,
                xOutOld: xOut,
                fee: _fee,
                m: m,
                r: _r,
                s: s,
                q: q,
                nTokens: _n,
                mu: MU,
                muSq: MU_SQ,
                countBelow: _countBelow,
                sumBelow: _sumBelow,
                sumSqBelow: _sumSqBelow
            });
            OrbitalMath.TickContext memory tctx = OrbitalMath.TickContext({
                ticksEnabled: _ticksEnabled,
                tickLowerBound: _tickLowerBound,
                currentTick: tick
            });
            (uint256 rawStar, bool willHit) = OrbitalMath.maxRawToNextTickDown(qctx, _tickmap, tctx, remaining);

            if (willHit && rawStar == 0) {
                (int32 nextTick, bool ok) = TickNav.nextDown(_tickmap, tick, _ticksEnabled, _tickLowerBound);
                if (!ok) {
                    break;
                }
                emit TickCrossed(tick, nextTick);
                tick = nextTick;
                continue;
            }

            uint256 toSpend = rawStar;

            if (minDy_ != 0 && rawDyOut < minDy_ && toSpend != 0) {
                uint256 targetRem = minDy_ - rawDyOut;
                uint256 high = toSpend;
                uint256 low = 1;
                uint256 chosen = 0;

                for (uint256 i = 0; i < 60 && low <= high; i++) {
                    uint256 mid = (low + high) >> 1;
                    qctx = OrbitalMath.QuoteContext({
                        tokenInConfig: tokenInConfig,
                        tokenOutConfig: tokenOutConfig,
                        xInOld: xIn,
                        xOutOld: xOut,
                        fee: _fee,
                        m: m,
                        r: _r,
                        s: s,
                        q: q,
                        nTokens: _n,
                        mu: MU,
                        muSq: MU_SQ,
                        countBelow: _countBelow,
                        sumBelow: _sumBelow,
                        sumSqBelow: _sumSqBelow
                    });
                    (uint256 outMid, bool crossedMid,,) = OrbitalMath.quoteExactIn(qctx, mid);

                    if (crossedMid) {
                        if (mid == 0) {
                            break;
                        }

                        high = mid - 1;
                        continue;
                    }

                    if (outMid >= targetRem) {
                        chosen = mid;
                        if (mid == 0) {
                            break;
                        }
                        high = mid - 1;
                    } else {
                        low = mid + 1;
                    }
                }

                if (chosen != 0 && chosen < toSpend) {
                    toSpend = chosen;
                }
            }

            if (toSpend == 0) {
                break;
            }

            qctx = OrbitalMath.QuoteContext({
                tokenInConfig: tokenInConfig,
                tokenOutConfig: tokenOutConfig,
                xInOld: xIn,
                xOutOld: xOut,
                fee: _fee,
                m: m,
                r: _r,
                s: s,
                q: q,
                nTokens: _n,
                mu: MU,
                muSq: MU_SQ,
                countBelow: _countBelow,
                sumBelow: _sumBelow,
                sumSqBelow: _sumSqBelow
            });
            (uint256 segmentOut, uint256 xInNew, uint256 xOutNew, uint256 sNew, uint256 qNew) =
                OrbitalMath.simulateSegment(qctx, toSpend);

            if (segmentOut == 0) {
                break;
            }

            tokenInConfig.reserve = uint128(xInNew);
            tokenOutConfig.reserve = uint128(xOutNew);
            _sumRes = sNew;
            _sumSq = qNew;

            _applySegmentAccounting(tokenIn_, tokenInConfig, xIn, toSpend, _fee, MU);

            xIn = xInNew;
            xOut = xOutNew;
            s = sNew;
            q = qNew;

            rawDyOut += segmentOut;
            rawDxUsed += toSpend;
            remaining -= toSpend;

            if (rawDyOut >= minDy_) {
                break;
            }

            if (willHit) {
                (int32 nextTick, bool ok) = TickNav.nextDown(_tickmap, tick, _ticksEnabled, _tickLowerBound);
                if (!ok) {
                    break;
                }
                emit TickCrossed(tick, nextTick);
                tick = nextTick;
            }
        }

        if (rawDyOut == 0) {
            revert InvalidAmount(rawDyOut);
        }
        if (rawDyOut < minDy_) {
            revert InsufficientLiquidity(rawDyOut, minDy_);
        }

        tokenOut_.safeTransfer(to_, rawDyOut);

        if (rawDxUsed < rawDxCap_) {
            tokenIn_.safeTransfer(msg.sender, rawDxCap_ - rawDxUsed);
        }

        if (tick != _currentTick) {
            _currentTick = tick;
            emit CurrentTickSet(tick);
        }

        return (rawDyOut, rawDxUsed);
    }

    // TODO: implement swapExactOut in O(1)
    function _swapExactOut(
        address, /*tokenIn_*/
        address, /*tokenOut_*/
        uint256, /*rawDxCap_*/
        uint256, /*minDy_*/
        address /*to_*/
    ) private pure returns (uint256, uint256) {
        revert NotImplemented();
    }
}
