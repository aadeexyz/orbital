// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {WadScale} from "../src/libraries/WadScale.sol";

contract WadScaleTest is Test {
    function test_computeScale64_decimals6() public pure {
        (bool up, uint64 f) = WadScale.computeScale64(6);
        assertTrue(up);
        assertEq(f, 1_000_000_000_000);
    }

    function test_computeScale64_decimals18() public pure {
        (bool up, uint64 f) = WadScale.computeScale64(18);
        assertTrue(up);
        assertEq(f, 1);
    }

    function test_computeScale64_decimals24() public pure {
        (bool up, uint64 f) = WadScale.computeScale64(24);
        assertFalse(up);
        assertEq(f, 1_000_000);
    }

    function test_roundTrip_scaleUp_decimals6() public pure {
        (bool up, uint64 f) = WadScale.computeScale64(6);
        uint256 raw = 123_456;
        uint256 wad = WadScale.toWad(raw, up, f);
        uint256 back = WadScale.fromWad(wad, up, f);
        assertEq(back, raw);
    }

    function test_roundTrip_scaleDown_decimals24_multipleOfFactor() public pure {
        (bool up, uint64 f) = WadScale.computeScale64(24);
        uint256 raw = 123_456 * uint256(f);
        uint256 wad = WadScale.toWad(raw, up, f);
        uint256 back = WadScale.fromWad(wad, up, f);
        assertEq(back, raw);
    }

    function test_toWadSafe_scaleUp_noOverflow_atLimit() public pure {
        uint64 factor = type(uint64).max;
        uint256 limit = type(uint256).max / uint256(factor);
        (bool ok, uint256 wad) = WadScale.toWadSafe(limit, true, factor);
        assertTrue(ok);
        assertEq(wad, limit * uint256(factor));
    }

    function test_toWadSafe_scaleUp_overflow_detected() public pure {
        uint64 factor = type(uint64).max;
        uint256 limit = type(uint256).max / uint256(factor);
        (bool ok, uint256 wad) = WadScale.toWadSafe(limit + 1, true, factor);
        assertFalse(ok);
        assertEq(wad, 0);
    }

    function test_toWadSafe_scaleDown_divides() public pure {
        uint64 factor = 1_000_000;
        (bool ok, uint256 wad) = WadScale.toWadSafe(123_456_789, false, factor);
        assertTrue(ok);
        assertEq(wad, 123_456_789 / factor);
    }

    function test_zeroInputs_areZero() public pure {
        (bool up, uint64 f) = WadScale.computeScale64(18);
        assertTrue(up);
        assertEq(f, 1);
        assertEq(WadScale.toWad(0, up, f), 0);
        assertEq(WadScale.fromWad(0, up, f), 0);
        (bool ok, uint256 w) = WadScale.toWadSafe(0, up, f);
        assertTrue(ok);
        assertEq(w, 0);
    }
}
