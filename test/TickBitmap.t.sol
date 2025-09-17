// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {TickBitmapHarness} from "./helpers/harnesses/TickBitmap.sol";

contract TickBitmapTest is Test {
    TickBitmapHarness h;

    uint256 constant NF = type(uint256).max;

    function setUp() public {
        h = new TickBitmapHarness();
    }

    function test_set_get_unset_basic() public {
        uint256 i = _index(7, 42);
        assertFalse(h.get(i));

        h.set(i);
        assertTrue(h.get(i));
        assertEq(h.wordAt(7), 1 << 42);

        h.unset(i);
        assertFalse(h.get(i));
        assertEq(h.wordAt(7), 0);
    }

    function test_set_idempotent_doubleSet_ok() public {
        uint256 i = _index(9, 3);
        h.set(i);
        h.set(i);
        assertTrue(h.get(i));
        assertEq(h.wordAt(9), 1 << 3);
    }

    function test_meta_bit_sets_on_first_bit_and_clears_on_last_unset() public {
        uint256 wIdx = 12345;
        uint256 bitA = 17;
        uint256 bitB = 200;

        uint256 sIdx = _superIndex(wIdx);
        uint256 sBit = _superBit(wIdx);

        assertEq(h.metaAt(sIdx), 0);

        h.set(_index(wIdx, bitA));
        assertEq(h.wordAt(wIdx), 1 << bitA);
        assertEq((h.metaAt(sIdx) >> sBit) & 1, 1);

        h.set(_index(wIdx, bitB));
        assertEq(h.wordAt(wIdx), (1 << bitA) | (1 << bitB));
        assertEq((h.metaAt(sIdx) >> sBit) & 1, 1);

        h.unset(_index(wIdx, bitA));
        assertEq(h.wordAt(wIdx), (1 << bitB));
        assertEq((h.metaAt(sIdx) >> sBit) & 1, 1);

        h.unset(_index(wIdx, bitB));
        assertEq(h.wordAt(wIdx), 0);
        assertEq((h.metaAt(sIdx) >> sBit) & 1, 0);
    }

    function test_nextSet_sameWord_hits_current_and_then_next() public {
        uint256 w = 50;
        uint256 i0 = _index(w, 10);
        uint256 i1 = _index(w, 200);
        h.set(i0);
        h.set(i1);

        uint256 r0 = h.nextSet(i0, _index(w, 255));
        assertEq(r0, i0);

        uint256 r1 = h.nextSet(_index(w, 11), _index(w, 255));
        assertEq(r1, i1);
    }

    function test_nextSet_respects_upTo_bound() public {
        uint256 w = 60;
        uint256 i = _index(w, 100);
        h.set(i);

        uint256 nf = h.nextSet(_index(w, 0), _index(w, 99));
        assertEq(nf, NF);

        uint256 ok = h.nextSet(_index(w, 0), i);
        assertEq(ok, i);
    }

    function test_nextSet_crosses_words_and_superwords() public {
        uint256 wLate = (2 << 8) + 3;
        uint256 iLate = _index(wLate, 1);
        h.set(iLate);

        uint256 r = h.nextSet(_index(0, 0), _index(wLate, 255));
        assertEq(r, iLate);
    }

    function test_nextSet_from_gt_upTo_returns_not_found() public view {
        uint256 r = h.nextSet(1000, 999);
        assertEq(r, NF);
    }

    function test_prevSet_sameWord_hits_current_and_prior() public {
        uint256 w = 77;
        uint256 i0 = _index(w, 1);
        uint256 i1 = _index(w, 250);
        h.set(i0);
        h.set(i1);

        uint256 r0 = h.prevSet(i1, _index(w, 0));
        assertEq(r0, i1);

        uint256 r1 = h.prevSet(_index(w, 200), _index(w, 0));
        assertEq(r1, i0);
    }

    function test_prevSet_respects_downTo_bound() public {
        uint256 w = 88;
        uint256 i = _index(w, 100);
        h.set(i);

        uint256 nf = h.prevSet(_index(w, 255), _index(w, 101));
        assertEq(nf, NF);

        uint256 ok = h.prevSet(_index(w, 255), i);
        assertEq(ok, i);
    }

    function test_prevSet_crosses_words_and_superwords() public {
        uint256 wEarly = (1 << 8) | 7;
        uint256 iEarly = _index(wEarly, 200);
        h.set(iEarly);

        uint256 from = _index((3 << 8) | 128, 10);
        uint256 r = h.prevSet(from, _index(0, 0));
        assertEq(r, iEarly);
    }

    function test_prevSet_from_lt_downTo_returns_not_found() public view {
        uint256 r = h.prevSet(999, 1000);
        assertEq(r, NF);
    }

    function test_edges_bitpos_0_and_255_and_word_boundaries() public {
        uint256 w = 5;
        uint256 iMin = _index(w, 0);
        uint256 iMax = _index(w, 255);
        h.set(iMin);
        h.set(iMax);

        assertEq(h.nextSet(_index(w, 0), _index(w, 255)), iMin);
        assertEq(h.nextSet(_index(w, 1), _index(w, 255)), iMax);

        assertEq(h.prevSet(_index(w, 255), _index(w, 0)), iMax);
        assertEq(h.prevSet(_index(w, 254), _index(w, 0)), iMin);
    }

    function _index(uint256 wordIndex, uint256 bitPos) private pure returns (uint256) {
        return (wordIndex << 8) | bitPos;
    }

    function _superIndex(uint256 wordIndex) private pure returns (uint256) {
        return wordIndex >> 8;
    }

    function _superBit(uint256 wordIndex) private pure returns (uint256) {
        return wordIndex & 0xff;
    }
}
