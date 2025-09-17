// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {TickNav} from "../src/libraries/TickNav.sol";
import {TickNavHarness} from "./helpers/harnesses/TickNav.sol";

contract TickNavTest is Test {
    TickNavHarness h;

    function setUp() public {
        h = new TickNavHarness();
    }

    function test_toIndex_fromIndex_roundtrip_zero_pos_neg() public pure {
        int32[5] memory ticks = [int32(type(int32).min), int32(-1), int32(0), int32(1), int32(type(int32).max)];

        for (uint256 i = 0; i < ticks.length; i++) {
            int32 t = ticks[i];
            uint256 idx = TickNav.toIndex(t);
            int32 back = TickNav.fromIndex(idx);
            assertEq(back, t);
        }
    }

    function test_toIndex_minMapsToZero_maxMapsToUint32Max() public pure {
        uint256 idxMin = TickNav.toIndex(type(int32).min);
        uint256 idxMax = TickNav.toIndex(type(int32).max);
        assertEq(idxMin, 0);
        assertEq(idxMax, uint256(type(uint32).max));
    }

    function test_nextUp_basicOrdering() public {
        h.set(_toIndex(-10));
        h.set(_toIndex(0));
        h.set(_toIndex(42));

        (int32 t1, bool ok1) = h.nextUp(-10);
        assertTrue(ok1);
        assertEq(t1, 0);

        (int32 t2, bool ok2) = h.nextUp(0);
        assertTrue(ok2);
        assertEq(t2, 42);

        (int32 t3, bool ok3) = h.nextUp(41);
        assertTrue(ok3);
        assertEq(t3, 42);

        (, bool ok4) = h.nextUp(42);
        assertFalse(ok4);
    }

    function test_nextDown_basicWithLowerBound() public {
        h.set(_toIndex(-100));
        h.set(_toIndex(0));
        h.set(_toIndex(50));

        uint256 lb = _toIndex(-100);

        (int32 td1, bool ok1) = h.nextDown(0, true, lb);
        assertTrue(ok1);
        assertEq(td1, -100);

        (, bool ok2) = h.nextDown(-100, true, lb);
        assertFalse(ok2);
    }

    function test_nextDown_blocksBelowLowerBound() public {
        h.set(_toIndex(-200));
        h.set(_toIndex(-150));

        uint256 lb = _toIndex(-150);

        (int32 td, bool ok) = h.nextDown(-100, true, lb);
        assertTrue(ok);
        assertEq(td, -150);
    }

    function test_nextDown_ignoresLowerBoundWhenDisabled() public {
        h.set(_toIndex(-300));

        (int32 td, bool ok) = h.nextDown(12345, false, type(uint256).max);
        assertTrue(ok);
        assertEq(td, -300);
    }

    function test_nextDown_respectsBounds_noResult() public {
        h.set(_toIndex(10));

        (, bool ok) = h.nextDown(-1000, true, _toIndex(-1000));
        assertFalse(ok);
    }

    function _toIndex(int32 t) private pure returns (uint256) {
        return TickNav.toIndex(t);
    }
}
