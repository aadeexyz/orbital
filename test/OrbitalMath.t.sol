// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {OrbitalMath} from "../src/libraries/OrbitalMath.sol";
import {IPoolMetadata} from "../src/interfaces/IPoolMetadata.sol";

contract OrbitalMathTest is Test {
    function test_computeSBoundary_kZero_positiveS() public pure {
        uint256 inverseSqrtN = 5e17;
        uint128 s = OrbitalMath.computeSBoundary(1e18, 0, inverseSqrtN);
        assertGt(s, 0);
    }

    function test_computeSBoundaryRZero_zero() public pure {
        uint128 s = OrbitalMath.computeSBoundary(0, 123, 5e17);
        assertEq(s, 0);
    }

    function test_computeSBoundary_farShift_clampsToZero() public pure {
        uint128 r = 1e18;

        uint128 s = OrbitalMath.computeSBoundary(r, int128(int256(3e18)), 5e17);
        assertEq(s, 0);
    }

    function test_computeSBoundary_edgeEquality_zero() public pure {
        uint128 s = OrbitalMath.computeSBoundary(1e18, int128(int256(15e17)), 5e17);
        assertEq(s, 0);
    }

    function test_computeSBoundary_monotoneAround_rOverSqrtN() public pure {
        uint128 r = 1e18;
        uint256 inverseSqrtN = 5e17;
        uint128 s0 = OrbitalMath.computeSBoundary(r, int128(int256(5e17)), inverseSqrtN);
        uint128 s1 = OrbitalMath.computeSBoundary(r, int128(int256(6e17)), inverseSqrtN);
        assertLt(s1, s0);
    }

    function test_computeSBoundary_inverseSqrtN_nearOne_isNearZero() public pure {
        uint128 s = OrbitalMath.computeSBoundary(1e18, 0, 999_999_999_000_000_000);
        assertLt(s, 1e15);
    }

    function test_effectiveSums_mZero_identity() public pure {
        (uint256 sEff, uint256 qEff) = OrbitalMath.effectiveSums(7e18, 11e18, 3, 0);
        assertEq(sEff, 7e18);
        assertEq(qEff, 11e18);
    }

    function test_effectiveSums_addsVirtualM() public pure {
        (uint256 sEff, uint256 qEff) = OrbitalMath.effectiveSums(2e18, 3e18, 4, 1e18);
        assertEq(sEff, 2e18 + 4e18);
        assertEq(qEff, 3e18 + 4e18 + 4e18);
    }

    function test_inferSegmentR_saneAndMonotone() public pure {
        uint256 R1 = OrbitalMath.inferSegmentR(2e18, 2e18, 2, 0);
        assertGt(R1, 0);
        uint256 R2 = OrbitalMath.inferSegmentR(3e18, 2e18, 2, 0);
        assertGe(R2, R1);
    }

    function test_inferSegmentR_unsolvableReturnsZero() public pure {
        uint256 R = OrbitalMath.inferSegmentR(1e18, 3e18, 3, 0);
        assertEq(R, 0);
    }

    function test_quoteExactIn_noMu_noFee_positiveOut() public pure {
        IPoolMetadata.TokenConfig memory ti = _tokenConfig(true, 1);
        IPoolMetadata.TokenConfig memory to_ = _tokenConfig(true, 1);

        uint256 xIn = 10e18;
        uint256 xOut = 10e18;
        uint256 S = xIn + xOut;
        uint256 Q = OrbitalMath.squareWad(xIn) + OrbitalMath.squareWad(xOut);
        uint16 n = 2;
        uint256 m = 0;

        uint128 R = uint128(OrbitalMath.inferSegmentR(S, Q, n, m));
        assertGt(R, 0);

        OrbitalMath.QuoteContext memory q = _quoteContext(ti, to_, xIn, xOut, 0, m, R, S, Q, n, 0, 0, 0, 0, 0);

        (uint256 out, bool cross, bool atB, uint256 yEff) = OrbitalMath.quoteExactIn(q, 1e18);
        assertFalse(cross);
        assertFalse(atB);
        assertGt(out, 0);
        assertLt(yEff, xOut);
    }

    function test_quoteExactIn_feeReducesOutput() public pure {
        IPoolMetadata.TokenConfig memory ti = _tokenConfig(true, 1);
        IPoolMetadata.TokenConfig memory to_ = _tokenConfig(true, 1);

        uint256 xIn = 10e18;
        uint256 xOut = 10e18;
        uint256 S = xIn + xOut;
        uint256 Q = OrbitalMath.squareWad(xIn) + OrbitalMath.squareWad(xOut);
        uint16 n = 2;

        uint128 R = uint128(OrbitalMath.inferSegmentR(S, Q, n, 0));
        assertGt(R, 0);

        OrbitalMath.QuoteContext memory q0 = _quoteContext(ti, to_, xIn, xOut, 0, 0, R, S, Q, n, 0, 0, 0, 0, 0);
        OrbitalMath.QuoteContext memory q1 = _quoteContext(ti, to_, xIn, xOut, 3e15, 0, R, S, Q, n, 0, 0, 0, 0, 0);

        (uint256 out0,,,) = OrbitalMath.quoteExactIn(q0, 1e18);
        (uint256 out1,,,) = OrbitalMath.quoteExactIn(q1, 1e18);

        assertGt(out0, 0);
        assertGt(out1, 0);
        assertGt(out0, out1);
    }

    function test_quoteExactIn_muGuard_triggersCross() public pure {
        IPoolMetadata.TokenConfig memory ti = _tokenConfig(true, 1);
        IPoolMetadata.TokenConfig memory to_ = _tokenConfig(true, 1);

        uint256 xIn = 5e18;
        uint256 xOut = 5e18;
        uint256 S = xIn + xOut;
        uint256 Q = OrbitalMath.squareWad(xIn) + OrbitalMath.squareWad(xOut);
        uint16 n = 2;
        uint128 mu = 4e18;

        uint128 R = uint128(OrbitalMath.inferSegmentR(S, Q, n, 0));
        assertGt(R, 0);

        OrbitalMath.QuoteContext memory q =
            _quoteContext(ti, to_, xIn, xOut, 0, 0, R, S, Q, n, mu, OrbitalMath.squareWad(mu), 0, 0, 0);

        (, bool cross,,) = OrbitalMath.quoteExactIn(q, 2e18);
        assertTrue(cross);
    }

    function test_simulateSegment_updatesS_Q_consistently() public pure {
        IPoolMetadata.TokenConfig memory ti = _tokenConfig(true, 1);
        IPoolMetadata.TokenConfig memory to_ = _tokenConfig(true, 1);

        uint256 xIn = 8e18;
        uint256 xOut = 12e18;
        uint256 S = xIn + xOut;
        uint256 Q = OrbitalMath.squareWad(xIn) + OrbitalMath.squareWad(xOut);
        uint16 n = 2;

        uint128 R = uint128(OrbitalMath.inferSegmentR(S, Q, n, 0));
        OrbitalMath.QuoteContext memory q = _quoteContext(ti, to_, xIn, xOut, 0, 0, R, S, Q, n, 0, 0, 0, 0, 0);

        (uint256 outRaw, uint256 xInNew, uint256 xOutNew, uint256 Snew, uint256 Qnew) =
            OrbitalMath.simulateSegment(q, 2e18);

        assertGt(outRaw, 0);
        assertLt(xOutNew, xOut);
        assertGt(xInNew, xIn);

        uint256 dyWad = (xOut - xOutNew);
        assertEq(Snew, S + (xInNew - xIn) - dyWad);

        uint256 Qexp = Q - OrbitalMath.squareWad(xIn) - OrbitalMath.squareWad(xOut) + OrbitalMath.squareWad(xInNew)
            + OrbitalMath.squareWad(xOutNew);
        assertEq(Qnew, Qexp);
    }

    function _tokenConfig(bool up, uint64 f) private pure returns (IPoolMetadata.TokenConfig memory t) {
        t.supported = true;
        t.disabled = false;
        t.scaleUp = up;
        t.factor = f;
        t.decimals = 18;
        t.reserve = 0;
    }

    function _quoteContext(
        IPoolMetadata.TokenConfig memory ti,
        IPoolMetadata.TokenConfig memory to_,
        uint256 xIn,
        uint256 xOut,
        uint256 fee,
        uint256 m,
        uint128 R,
        uint256 S,
        uint256 Q,
        uint16 n,
        uint128 mu,
        uint256 muSq,
        uint16 cb,
        uint256 sb,
        uint256 ssb
    ) private pure returns (OrbitalMath.QuoteContext memory q) {
        q.tokenInConfig = ti;
        q.tokenOutConfig = to_;
        q.xInOld = xIn;
        q.xOutOld = xOut;
        q.fee = fee;
        q.m = m;
        q.r = R;
        q.s = S;
        q.q = Q;
        q.nTokens = n;
        q.mu = mu;
        q.muSq = muSq;
        q.countBelow = cb;
        q.sumBelow = sb;
        q.sumSqBelow = ssb;
    }
}
