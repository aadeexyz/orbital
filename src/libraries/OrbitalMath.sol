// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.30;

import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {IPoolMetadata} from "../interfaces/IPoolMetadata.sol";
import {WadScale} from "./WadScale.sol";
import {TickBitmap} from "./TickBitmap.sol";
import {TickNav} from "./TickNav.sol";

library OrbitalMath {
    using TickBitmap for TickBitmap.Bitmap;
    using TickNav for TickBitmap.Bitmap;

    struct QuoteContext {
        IPoolMetadata.TokenConfig tokenInConfig;
        IPoolMetadata.TokenConfig tokenOutConfig;
        uint256 xInOld;
        uint256 xOutOld;
        uint256 fee;
        uint256 m;
        uint128 r;
        uint256 s;
        uint256 q;
        uint16 nTokens;
        uint128 mu;
        uint256 muSq;
        uint16 countBelow;
        uint256 sumBelow;
        uint256 sumSqBelow;
    }

    struct TickContext {
        bool ticksEnabled;
        uint256 tickLowerBound;
        int32 currentTick;
    }

    function squareWad(uint256 x_) internal pure returns (uint256) {
        return FixedPointMathLib.mulWad(x_, x_);
    }

    function computeSBoundary(uint128 r_, int128 k_, uint256 inverseSqrtN_) internal pure returns (uint128) {
        if (r_ == 0) {
            return 0;
        }

        uint256 r = uint256(r_);
        uint256 rOverSqrtN = FixedPointMathLib.mulWad(r, inverseSqrtN_);

        int256 k = int256(k_);
        int256 shift = k - int256(rOverSqrtN);
        uint256 shiftAbs = FixedPointMathLib.abs(shift);

        uint256 rSq = squareWad(r);
        uint256 shiftSq = squareWad(shiftAbs);
        if (shiftSq >= rSq) {
            return 0;
        }

        uint256 disc = rSq - shiftSq;
        uint256 sSqrt = FixedPointMathLib.sqrt(disc);
        uint256 sFull = sSqrt * 1e9; // because we lost 9 decimals to the square root operation

        return sFull > type(uint128).max ? type(uint128).max : uint128(sFull);
    }

    function inferSegmentR(uint256 s_, uint256 q_, uint16 nTokens_, uint256 m_) internal pure returns (uint256) {
        if (nTokens_ < 2) return 0;

        (uint256 sEffective, uint256 qEffective) = effectiveSums(s_, q_, nTokens_, m_);
        uint256 a = uint256(nTokens_) - 1;
        uint256 left = sEffective * sEffective;
        uint256 right = a * FixedPointMathLib.WAD * qEffective;

        if (left < right) return 0;

        uint256 disc = left - right;
        uint256 sqrtTerm = FixedPointMathLib.sqrt(disc);

        return (sEffective + sqrtTerm) / a;
    }

    function effectiveSums(uint256 s_, uint256 q_, uint16 nTokens_, uint256 m_)
        internal
        pure
        returns (uint256, uint256)
    {
        if (m_ == 0 || nTokens_ == 0) return (s_, q_);

        uint256 twoMSOverW = FixedPointMathLib.mulWad(2 * m_, s_);
        uint256 nMSqOverW = FixedPointMathLib.mulWad(uint256(nTokens_) * m_, m_);

        return (s_ + uint256(nTokens_) * m_, q_ + twoMSOverW + nMSqOverW);
    }

    function effectiveConstantsAfterInputWithN(uint256 s0_, uint256 q0_, uint256 xOutOld_, uint256 m_, uint16 ntokens_)
        internal
        pure
        returns (uint256, uint256, uint256)
    {
        if (m_ == 0) {
            return (s0_ - xOutOld_, q0_ - squareWad(xOutOld_), xOutOld_);
        }
        uint256 nMinus1 = uint256(ntokens_) - 1;

        return (
            (s0_ - xOutOld_) + nMinus1 * m_,
            (q0_ - squareWad(xOutOld_)) + FixedPointMathLib.mulWad(2 * m_, (s0_ - xOutOld_))
                + FixedPointMathLib.mulWad(nMinus1 * m_, m_),
            xOutOld_ + m_
        );
    }

    function buildEffectiveConstantWithMuAndTick(
        uint256 xInOld_,
        uint256 xInNew_,
        uint256 xOutOld_,
        uint256 s_,
        uint256 q_,
        uint16 nTokens_,
        uint256 m_,
        uint128 mu_,
        uint256 muSq_,
        uint16 countBelow_,
        uint256 sumBelow_,
        uint256 sumSqBelow_
    ) internal pure returns (uint256, uint256, uint256) {
        uint256 s0 = s_ + (xInNew_ - xInOld_);
        uint256 q0 = q_ + squareWad(xInNew_) - squareWad(xInOld_);

        uint16 cb0 = countBelow_;
        uint256 sb0 = sumBelow_;
        uint256 ssqb0 = sumSqBelow_;

        if (mu_ != 0 && xInOld_ < mu_) {
            if (xInNew_ < mu_) {
                sb0 += (xInNew_ - xInOld_);
                ssqb0 += squareWad(xInNew_) - squareWad(xInOld_);
            } else {
                unchecked {
                    cb0 -= 1;
                }
                sb0 -= xInOld_;
                ssqb0 -= squareWad(xInOld_);
            }
        }

        uint16 cb1 = cb0;
        uint256 sb1 = sb0;
        uint256 ssqb1 = ssqb0;
        if (mu_ != 0 && xOutOld_ < mu_) {
            unchecked {
                cb1 -= 1;
            }
            sb1 -= xOutOld_;
            ssqb1 -= squareWad(xOutOld_);
        }

        uint256 zSum;
        uint256 zSqSum;
        if (mu_ == 0) {
            zSum = s0 - xOutOld_;
            zSqSum = q0 - squareWad(xOutOld_);
        } else {
            zSum = (s0 - xOutOld_) - sb1 + uint256(cb1) * uint256(mu_);
            zSqSum = (q0 - squareWad(xOutOld_)) - ssqb1 + uint256(cb1) * muSq_;
        }

        uint256 zOutOld = (mu_ != 0 && xOutOld_ < mu_) ? uint256(mu_) : xOutOld_;
        uint256 xOutEffective = (m_ == 0) ? zOutOld : zOutOld + m_;
        if (nTokens_ > 1 && m_ != 0) {
            uint256 nMinus1 = uint256(nTokens_ - 1);

            return (
                zSum + nMinus1 * m_,
                zSqSum + FixedPointMathLib.mulWad(2 * m_, zSum) + FixedPointMathLib.mulWad(nMinus1 * m_, m_),
                xOutEffective
            );
        }

        return (zSum, zSqSum, xOutEffective);
    }

    function quoteExactIn(QuoteContext memory qctx_, uint256 rawDxCap_)
        internal
        pure
        returns (uint256, bool, bool, uint256)
    {
        (bool ok, uint256 dx) = WadScale.toWadSafe(rawDxCap_, qctx_.tokenInConfig.scaleUp, qctx_.tokenInConfig.factor);
        if (!ok || dx == 0) {
            return (0, true, false, 0);
        }

        uint256 fee = FixedPointMathLib.mulWad(dx, qctx_.fee);
        uint256 dxNet = dx - fee;

        uint256 xInNew = qctx_.xInOld + dxNet;
        if (xInNew > type(uint128).max) {
            return (0, true, false, 0);
        }

        (uint256 sConst, uint256 qConst, uint256 xOutEffectiveOld) = buildEffectiveConstantWithMuAndTick(
            qctx_.xInOld,
            xInNew,
            qctx_.xOutOld,
            qctx_.s,
            qctx_.q,
            qctx_.nTokens,
            qctx_.m,
            qctx_.mu,
            qctx_.muSq,
            qctx_.countBelow,
            qctx_.sumBelow,
            qctx_.sumSqBelow
        );

        uint256 r = uint256(qctx_.r);
        if (r == 0) {
            return (0, true, false, 0);
        }

        uint256 rSq = r * r;
        int256 cp =
            int256(qConst * FixedPointMathLib.WAD) - int256(2 * r * sConst) + int256(uint256(qctx_.nTokens - 1) * rSq);
        int256 d = int256(rSq) - cp;
        if (d < 0) {
            return (0, true, false, 0);
        }

        uint256 sqrtD = FixedPointMathLib.sqrt(uint256(d));
        uint256 yEffectiveLow = (r > sqrtD) ? r - sqrtD : 0;
        if (yEffectiveLow > xOutEffectiveOld) {
            return (0, true, false, 0);
        }

        uint256 yPhysical = (qctx_.m == 0) ? yEffectiveLow : (yEffectiveLow >= qctx_.m) ? yEffectiveLow - qctx_.m : 0;
        bool atBoundary = (qctx_.mu != 0) && (yPhysical == qctx_.mu);
        if (qctx_.mu != 0 && yPhysical < qctx_.mu) {
            return (0, true, atBoundary, yEffectiveLow);
        }

        uint256 dy = xOutEffectiveOld - yEffectiveLow;
        uint256 outRaw = WadScale.fromWad(dy, qctx_.tokenOutConfig.scaleUp, qctx_.tokenOutConfig.factor);
        if (outRaw == 0) {
            return (0, true, atBoundary, yEffectiveLow);
        }

        return (outRaw, false, atBoundary, yEffectiveLow);
    }

    function simulateSegment(QuoteContext memory qctx_, uint256 rawDxCap_)
        internal
        pure
        returns (uint256, uint256, uint256, uint256, uint256)
    {
        (bool ok, uint256 dx) = WadScale.toWadSafe(rawDxCap_, qctx_.tokenInConfig.scaleUp, qctx_.tokenInConfig.factor);
        if (!ok || dx == 0) {
            return (0, qctx_.xInOld, qctx_.xOutOld, qctx_.s, qctx_.q);
        }

        uint256 fee = FixedPointMathLib.mulWad(dx, qctx_.fee);
        uint256 dxNet = dx - fee;
        uint256 xInNew = qctx_.xInOld + dxNet;
        uint256 s0 = qctx_.s + dxNet;
        uint256 q0 = qctx_.q + squareWad(xInNew) - squareWad(qctx_.xInOld);

        (uint256 sConst, uint256 qConst, uint256 xOutEffectiveOld) = buildEffectiveConstantWithMuAndTick(
            qctx_.xInOld,
            xInNew,
            qctx_.xOutOld,
            qctx_.s,
            qctx_.q,
            qctx_.nTokens,
            qctx_.m,
            qctx_.mu,
            qctx_.muSq,
            qctx_.countBelow,
            qctx_.sumBelow,
            qctx_.sumSqBelow
        );

        uint256 r = uint256(qctx_.r);
        if (r == 0) {
            return (0, qctx_.xInOld, qctx_.xOutOld, s0, q0);
        }

        uint256 rSq = r * r;
        int256 cp =
            int256(qConst * FixedPointMathLib.WAD) - int256(2 * r * sConst) + int256(uint256(qctx_.nTokens - 1) * rSq);
        int256 d = int256(rSq) - cp;
        if (d < 0) {
            return (0, qctx_.xInOld, qctx_.xOutOld, s0, q0);
        }

        uint256 sqrtD = FixedPointMathLib.sqrt(uint256(d));
        uint256 yEffectiveLow = (r > sqrtD) ? r - sqrtD : 0;
        if (yEffectiveLow > xOutEffectiveOld) {
            return (0, qctx_.xInOld, qctx_.xOutOld, s0, q0);
        }

        uint256 dy = xOutEffectiveOld - yEffectiveLow;
        if (dy > qctx_.xOutOld) {
            dy = qctx_.xOutOld;
        }

        uint256 rawDyOut = WadScale.fromWad(dy, qctx_.tokenOutConfig.scaleUp, qctx_.tokenOutConfig.factor);
        if (rawDyOut == 0) {
            return (0, qctx_.xInOld, qctx_.xOutOld, s0, q0);
        }

        uint256 dyWadEffective = WadScale.toWad(rawDyOut, qctx_.tokenOutConfig.scaleUp, qctx_.tokenOutConfig.factor);
        uint256 yPhysicalEffective = qctx_.xOutOld - dyWadEffective;
        uint256 xInFinal = xInNew + fee;

        return (
            rawDyOut,
            xInFinal,
            yPhysicalEffective,
            s0 - dyWadEffective + fee,
            q0 - squareWad(qctx_.xOutOld) + squareWad(yPhysicalEffective) + (squareWad(xInFinal) - squareWad(xInNew))
        );
    }

    function maxRawToNextTickDown(
        QuoteContext memory qctx_,
        TickBitmap.Bitmap storage tickmap_,
        TickContext memory tctx_,
        uint256 rawDxCap_
    ) internal view returns (uint256, bool) {
        (, bool hasLower) = tickmap_.nextDown(tctx_.currentTick, tctx_.ticksEnabled, tctx_.tickLowerBound);
        if (!hasLower) {
            return (rawDxCap_, false);
        }

        {
            (uint256 outFull2, bool crossFull2,, uint256 yEffectiveFull2) = quoteExactIn(qctx_, rawDxCap_);
            if (!crossFull2 && yEffectiveFull2 >= qctx_.m && outFull2 > 0) {
                return (rawDxCap_, false);
            }
        }

        uint256 lo2 = 0;
        uint256 hi2 = rawDxCap_;
        for (uint256 it2 = 0; it2 < 40; ++it2) {
            if (lo2 == hi2) break;

            uint256 mid2 = (lo2 + hi2 + 1) >> 1;
            (uint256 outMid2, bool crossMid2,, uint256 yEffectiveMid2) = quoteExactIn(qctx_, mid2);

            if (crossMid2 || yEffectiveMid2 < qctx_.m) {
                hi2 = mid2 - 1;
                continue;
            }

            if (outMid2 > 0) {
                lo2 = mid2;
            } else {
                hi2 = mid2 - 1;
            }
        }

        return (lo2, true);
    }
}
