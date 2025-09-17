// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Pool} from "../src/Pool.sol";
import {OrbitalMath} from "../src/libraries/OrbitalMath.sol";
import {IPoolMetadata} from "../src/interfaces/IPoolMetadata.sol";
import {MockERC20} from "./helpers/mocks/ERC20.sol";

contract PoolTest is Test {
    Pool internal pool;
    MockERC20 internal token0;
    MockERC20 internal token1;
    MockERC20 internal token2;
    MockERC20 internal token3;
    MockERC20 internal tokenBad;

    address internal OWNER = address(this);
    address internal USER = address(0xBEEF);

    uint256 internal constant ONE = 1e18;

    function setUp() public {
        token0 = new MockERC20("Token0", "T0", 6);
        token1 = new MockERC20("Token1", "T1", 18);
        token2 = new MockERC20("Token2", "T2", 8);
        token3 = new MockERC20("Token3", "T3", 24);
        tokenBad = new MockERC20("Bad", "BAD", 30);

        token0.mint(OWNER, _units(6, 1_000_000));
        token1.mint(OWNER, _units(18, 1_000_000));
        token2.mint(OWNER, _units(8, 1_000_000));
        token3.mint(OWNER, _units(24, 1_000_000));

        token0.mint(USER, _units(6, 1_000_000));
        token1.mint(USER, _units(18, 1_000_000));
        token2.mint(USER, _units(8, 1_000_000));
        token3.mint(USER, _units(24, 1_000_000));

        pool = new Pool(1e18, 0, OWNER);
    }

    function _units(uint8 dec, uint256 whole) private pure returns (uint256) {
        return whole * (10 ** dec);
    }

    function _toRawFromWad(uint8 dec, uint256 wad) private pure returns (uint256) {
        if (dec <= 18) {
            uint256 factor = 10 ** (18 - dec);
            return wad / factor;
        } else {
            uint256 factor = 10 ** (dec - 18);
            return wad * factor;
        }
    }

    function _tokCfg(uint8 dec) private pure returns (IPoolMetadata.TokenConfig memory t) {
        t.supported = true;
        t.disabled = false;
        t.decimals = dec;
        if (dec <= 18) {
            t.scaleUp = true;
            t.factor = uint64(10 ** (18 - dec));
        } else {
            t.scaleUp = false;
            t.factor = uint64(10 ** (dec - 18));
        }
    }

    function _qc(
        IPoolMetadata.TokenConfig memory ti,
        IPoolMetadata.TokenConfig memory to_,
        uint256 xInWad,
        uint256 xOutWad,
        uint256 fee,
        uint256 m,
        uint128 R,
        uint256 S,
        uint256 Q,
        uint16 n,
        uint128 mu,
        uint256 muSq
    ) private pure returns (OrbitalMath.QuoteContext memory q) {
        q.tokenInConfig = ti;
        q.tokenOutConfig = to_;
        q.xInOld = xInWad;
        q.xOutOld = xOutWad;
        q.fee = fee;
        q.m = m;
        q.r = R;
        q.s = S;
        q.q = Q;
        q.nTokens = n;
        q.mu = mu;
        q.muSq = muSq;
        q.countBelow = 0;
        q.sumBelow = 0;
        q.sumSqBelow = 0;
    }

    function _sumSQ(uint256[] memory wads) private pure returns (uint256 S, uint256 Q) {
        for (uint256 i = 0; i < wads.length; ++i) {
            S += wads[i];
            Q += OrbitalMath.squareWad(wads[i]);
        }
    }

    function _solveDxForMinDy(OrbitalMath.QuoteContext memory q, uint256 targetOutRaw)
        private
        pure
        returns (uint256 dxMinRaw, uint256 outAtDx)
    {
        uint256 lo = 0;
        uint256 hi = 1;
        for (uint256 i = 0; i < 64; ++i) {
            (uint256 out, bool cross,,) = OrbitalMath.quoteExactIn(q, hi);
            if (!cross && out >= targetOutRaw) break;
            hi <<= 1;
            if (hi == 0) return (0, 0);
        }
        for (uint256 it = 0; it < 60 && lo < hi; ++it) {
            uint256 mid = (lo + hi) >> 1;
            (uint256 out, bool cross,,) = OrbitalMath.quoteExactIn(q, mid);
            if (cross || out < targetOutRaw) lo = mid + 1;
            else hi = mid;
        }
        (uint256 out2, bool cross2,,) = OrbitalMath.quoteExactIn(q, hi);
        require(!cross2 && out2 >= targetOutRaw, "solver-no-solution");
        return (hi, out2);
    }

    function test_listToken_requiresPaused() public {
        token0.approve(address(pool), type(uint256).max);
        vm.expectRevert();
        pool.listToken(address(token0), _units(6, 100_000));

        pool.pause();
        pool.listToken(address(token0), _units(6, 100_000));

        token1.approve(address(pool), type(uint256).max);
        pool.listToken(address(token1), _units(18, 100_000));
    }

    function test_listToken_rejectsDecimalsGT24() public {
        pool.pause();
        tokenBad.approve(address(pool), type(uint256).max);
        vm.expectRevert();

        pool.listToken(address(tokenBad), 1 * (10 ** 30));
    }

    function test_onlyOwner_can_listToken() public {
        pool.pause();

        vm.prank(USER);
        token0.approve(address(pool), type(uint256).max);

        vm.prank(USER);
        vm.expectRevert();
        pool.listToken(address(token0), _units(6, 10_000));
    }

    function test_finalize_locksAndEnablesSwap_flow() public {
        pool.pause();
        token0.approve(address(pool), type(uint256).max);
        token1.approve(address(pool), type(uint256).max);
        pool.listToken(address(token0), _units(6, 500_000));
        pool.listToken(address(token1), _units(18, 500_000));

        pool.unpause();
        vm.expectRevert();
        pool.swapExactIn(address(token0), address(token1), _units(6, 1_000), 0, OWNER, block.timestamp + 1);

        pool.finalize();

        token0.approve(address(pool), type(uint256).max);

        uint256 bal0Before = token0.balanceOf(OWNER);
        uint256 bal1Before = token1.balanceOf(OWNER);

        (uint256 amountOut, uint256 amountInUsed) =
            pool.swapExactIn(address(token0), address(token1), _units(6, 1_000), 0, OWNER, block.timestamp + 1);

        assertGt(amountOut, 0);
        assertGt(amountInUsed, 0);

        uint256 bal0After = token0.balanceOf(OWNER);
        uint256 bal1After = token1.balanceOf(OWNER);

        assertEq(bal0Before - bal0After, amountInUsed);
        assertEq(bal1After - bal1Before, amountOut);
    }

    function test_swap_rejects_whenPaused_orDeadline() public {
        pool.pause();
        token0.approve(address(pool), type(uint256).max);
        token1.approve(address(pool), type(uint256).max);
        pool.listToken(address(token0), _units(6, 100_000));
        pool.listToken(address(token1), _units(18, 100_000));
        pool.finalize();

        vm.expectRevert();
        pool.swapExactIn(address(token0), address(token1), _units(6, 100), 0, OWNER, block.timestamp + 1);

        pool.unpause();
        vm.expectRevert();
        pool.swapExactIn(address(token0), address(token1), _units(6, 100), 0, OWNER, block.timestamp - 1);
    }

    function test_swapExactIn_refund_path_with_minDy() public {
        pool.pause();
        token0.approve(address(pool), type(uint256).max);
        token1.approve(address(pool), type(uint256).max);
        pool.listToken(address(token0), _units(6, 300_000));
        pool.listToken(address(token1), _units(18, 300_000));
        pool.finalize();
        pool.unpause();

        token0.approve(address(pool), type(uint256).max);

        uint256 capRaw = _units(6, 10_000);
        uint256 minDyRaw = 1;

        uint256 bal0Before = token0.balanceOf(OWNER);
        uint256 bal1Before = token1.balanceOf(OWNER);

        (uint256 outAmt, uint256 inUsed) =
            pool.swapExactIn(address(token0), address(token1), capRaw, minDyRaw, OWNER, block.timestamp + 1);

        assertGt(outAmt, 0);
        assertGe(outAmt, minDyRaw);
        assertLt(inUsed, capRaw);

        uint256 bal0After = token0.balanceOf(OWNER);
        uint256 bal1After = token1.balanceOf(OWNER);

        assertEq(bal0Before - bal0After, inUsed);
        assertEq(bal1After - bal1Before, outAmt);
    }

    function test_swapExactIn_insufficientLiquidity_reverts_on_high_minDy() public {
        pool.pause();
        token0.approve(address(pool), type(uint256).max);
        token1.approve(address(pool), type(uint256).max);
        pool.listToken(address(token0), _units(6, 50_000));
        pool.listToken(address(token1), _units(18, 50_000));
        pool.finalize();
        pool.unpause();

        token0.approve(address(pool), type(uint256).max);

        vm.expectRevert();

        pool.swapExactIn(
            address(token0), address(token1), _units(6, 1_000), type(uint256).max / 2, OWNER, block.timestamp + 1
        );
    }

    function test_deposit_reverts_if_notSupported() public {
        vm.expectRevert();
        pool.deposit(address(token0), _units(6, 1));
    }

    function test_deposit_updatesbalances_and_allows_anyone() public {
        pool.pause();
        token0.approve(address(pool), type(uint256).max);
        pool.listToken(address(token0), _units(6, 10_000));
        pool.unpause();

        vm.startPrank(USER);
        token0.approve(address(pool), type(uint256).max);
        uint256 userBefore = token0.balanceOf(USER);
        uint256 poolBefore = token0.balanceOf(address(pool));

        pool.deposit(address(token0), _units(6, 250));

        uint256 userAfter = token0.balanceOf(USER);
        uint256 poolAfter = token0.balanceOf(address(pool));
        vm.stopPrank();

        assertEq(userBefore - userAfter, _units(6, 250));
        assertEq(poolAfter - poolBefore, _units(6, 250));
    }

    function test_setTokenDisabled_blocks_deposit() public {
        pool.pause();
        token0.approve(address(pool), type(uint256).max);
        pool.listToken(address(token0), _units(6, 10_000));
        pool.unpause();

        pool.setTokenDisabled(address(token0), true);

        vm.startPrank(USER);
        token0.approve(address(pool), type(uint256).max);
        vm.expectRevert();
        pool.deposit(address(token0), _units(6, 1));
        vm.stopPrank();
    }

    function test_setFee_upperBound() public {
        pool.setFee(0);
        pool.setFee(5e15);
        vm.expectRevert();
        pool.setFee(1e16 + 1);
    }

    function test_setMaxSteps_bounds() public {
        vm.expectRevert();
        pool.setMaxSteps(0);

        pool.setMaxSteps(10);

        vm.expectRevert();
        pool.setMaxSteps(101);
    }

    function test_swap_guard_sameToken_zeroAmount_invalidTo() public {
        pool.pause();
        token0.approve(address(pool), type(uint256).max);
        token1.approve(address(pool), type(uint256).max);
        pool.listToken(address(token0), _units(6, 100_000));
        pool.listToken(address(token1), _units(18, 100_000));
        pool.finalize();
        pool.unpause();

        token0.approve(address(pool), type(uint256).max);

        vm.expectRevert();
        pool.swapExactIn(address(token0), address(token0), 1, 0, OWNER, block.timestamp + 1);

        vm.expectRevert();
        pool.swapExactIn(address(token0), address(token1), 0, 0, OWNER, block.timestamp + 1);

        vm.expectRevert();
        pool.swapExactIn(address(token0), address(token1), 1, 0, address(0), block.timestamp + 1);
    }

    function test_setCurrentTick_invalid_without_ticks() public {
        vm.expectRevert();
        pool.setCurrentTick(0);
    }

    function test_swapExactIn_exact_math_4tokens_noTicks_noFee_matches_reference() public {
        pool.pause();
        token0.approve(address(pool), type(uint256).max);
        token1.approve(address(pool), type(uint256).max);
        token2.approve(address(pool), type(uint256).max);
        token3.approve(address(pool), type(uint256).max);

        uint256 a0W = 500_000 * ONE;
        uint256 a1W = 420_000 * ONE;
        uint256 a2W = 310_000 * ONE;
        uint256 a3W = 260_000 * ONE;

        pool.listToken(address(token0), _toRawFromWad(token0.decimals(), a0W));
        pool.listToken(address(token1), _toRawFromWad(token1.decimals(), a1W));
        pool.listToken(address(token2), _toRawFromWad(token2.decimals(), a2W));
        pool.listToken(address(token3), _toRawFromWad(token3.decimals(), a3W));
        pool.finalize();
        pool.unpause();

        uint256[] memory xs = new uint256[](4);
        xs[0] = a0W;
        xs[1] = a1W;
        xs[2] = a2W;
        xs[3] = a3W;
        (uint256 S, uint256 Q) = _sumSQ(xs);

        uint16 n = 4;
        uint256 m = 0;
        uint128 mu = 1e18;
        uint256 muSq = OrbitalMath.squareWad(mu);
        uint128 R = uint128(OrbitalMath.inferSegmentR(S, Q, n, m));
        assertGt(R, 0);

        IPoolMetadata.TokenConfig memory ti = _tokCfg(token0.decimals());
        IPoolMetadata.TokenConfig memory to_ = _tokCfg(token3.decimals());
        OrbitalMath.QuoteContext memory qref = _qc(ti, to_, a0W, a3W, 0, m, R, S, Q, n, mu, muSq);

        uint256 dxW = 1_000 * ONE;
        uint256 capRaw = _toRawFromWad(token0.decimals(), dxW);

        (uint256 refOut,,,,) = OrbitalMath.simulateSegment(qref, capRaw);
        assertGt(refOut, 0);

        token0.approve(address(pool), type(uint256).max);
        (uint256 outAmt, uint256 inUsed) =
            pool.swapExactIn(address(token0), address(token3), capRaw, 0, OWNER, block.timestamp + 1);

        assertEq(inUsed, capRaw);
        assertEq(outAmt, refOut);
    }

    function test_swapExactIn_exact_minDy_solver_4tokens_matches_reference_dx() public {
        pool.pause();
        token0.approve(address(pool), type(uint256).max);
        token1.approve(address(pool), type(uint256).max);
        token2.approve(address(pool), type(uint256).max);
        token3.approve(address(pool), type(uint256).max);

        uint256 b0W = 450_000 * ONE;
        uint256 b1W = 380_000 * ONE;
        uint256 b2W = 510_000 * ONE;
        uint256 b3W = 420_000 * ONE;

        pool.listToken(address(token0), _toRawFromWad(token0.decimals(), b0W));
        pool.listToken(address(token1), _toRawFromWad(token1.decimals(), b1W));
        pool.listToken(address(token2), _toRawFromWad(token2.decimals(), b2W));
        pool.listToken(address(token3), _toRawFromWad(token3.decimals(), b3W));
        pool.finalize();
        pool.unpause();

        uint256[] memory xs = new uint256[](4);
        xs[0] = b0W;
        xs[1] = b1W;
        xs[2] = b2W;
        xs[3] = b3W;
        (uint256 S, uint256 Q) = _sumSQ(xs);

        uint16 n = 4;
        uint256 m = 0;
        uint128 mu = 1e18;
        uint256 muSq = OrbitalMath.squareWad(mu);
        uint128 R = uint128(OrbitalMath.inferSegmentR(S, Q, n, m));

        IPoolMetadata.TokenConfig memory ti = _tokCfg(token0.decimals());
        IPoolMetadata.TokenConfig memory to_ = _tokCfg(token3.decimals());
        OrbitalMath.QuoteContext memory qref = _qc(ti, to_, b0W, b3W, 0, m, R, S, Q, n, mu, muSq);

        uint256 targetOutW = 55_000 * ONE;
        uint256 targetOutRaw = _toRawFromWad(token3.decimals(), targetOutW);

        (uint256 dxExpected, uint256 outAtDx) = _solveDxForMinDy(qref, targetOutRaw);
        assertGe(outAtDx, targetOutRaw);
        assertGt(dxExpected, 0);

        token0.approve(address(pool), type(uint256).max);
        (uint256 outAmt, uint256 inUsed) = pool.swapExactIn(
            address(token0), address(token3), dxExpected + 1000, targetOutRaw, OWNER, block.timestamp + 1
        );

        assertEq(inUsed, dxExpected);
        assertEq(outAmt, outAtDx);
    }

    function test_swapExactIn_exact_with_fee_4tokens_matches_reference() public {
        pool.pause();
        token0.approve(address(pool), type(uint256).max);
        token1.approve(address(pool), type(uint256).max);
        token2.approve(address(pool), type(uint256).max);
        token3.approve(address(pool), type(uint256).max);

        uint256 c0W = 600_000 * ONE;
        uint256 c1W = 500_000 * ONE;
        uint256 c2W = 470_000 * ONE;
        uint256 c3W = 520_000 * ONE;

        pool.listToken(address(token0), _toRawFromWad(token0.decimals(), c0W));
        pool.listToken(address(token1), _toRawFromWad(token1.decimals(), c1W));
        pool.listToken(address(token2), _toRawFromWad(token2.decimals(), c2W));
        pool.listToken(address(token3), _toRawFromWad(token3.decimals(), c3W));
        pool.finalize();
        pool.unpause();

        pool.setFee(5e15);

        uint256[] memory xs = new uint256[](4);
        xs[0] = c0W;
        xs[1] = c1W;
        xs[2] = c2W;
        xs[3] = c3W;
        (uint256 S, uint256 Q) = _sumSQ(xs);

        uint16 n = 4;
        uint256 m = 0;
        uint128 mu = 1e18;
        uint256 muSq = OrbitalMath.squareWad(mu);
        uint128 R = uint128(OrbitalMath.inferSegmentR(S, Q, n, m));

        IPoolMetadata.TokenConfig memory ti = _tokCfg(token0.decimals());
        IPoolMetadata.TokenConfig memory to_ = _tokCfg(token3.decimals());
        OrbitalMath.QuoteContext memory qref = _qc(ti, to_, c0W, c3W, 5e15, m, R, S, Q, n, mu, muSq);

        uint256 dxW = 2_345 * ONE;
        uint256 capRaw = _toRawFromWad(token0.decimals(), dxW);
        (uint256 refOut,,,,) = OrbitalMath.simulateSegment(qref, capRaw);

        token0.approve(address(pool), type(uint256).max);
        (uint256 outAmt, uint256 inUsed) =
            pool.swapExactIn(address(token0), address(token3), capRaw, 0, OWNER, block.timestamp + 1);

        assertEq(inUsed, capRaw);
        assertEq(outAmt, refOut);
    }
}
