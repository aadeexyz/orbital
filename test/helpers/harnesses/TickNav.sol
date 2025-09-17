// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.30;

import {TickBitmap} from "../../../src/libraries/TickBitmap.sol";
import {TickNav} from "../../../src/libraries/TickNav.sol";

contract TickNavHarness {
    using TickBitmap for TickBitmap.Bitmap;

    TickBitmap.Bitmap internal bm;

    function set(uint256 index) external {
        bm.set(index);
    }

    function unset(uint256 index) external {
        bm.unset(index);
    }

    function get(uint256 index) external view returns (bool) {
        return bm.get(index);
    }

    function nextUp(int32 from) external view returns (int32, bool) {
        return TickNav.nextUp(bm, from);
    }

    function nextDown(int32 from, bool ticksEnabled, uint256 tickLowerBound) external view returns (int32, bool) {
        return TickNav.nextDown(bm, from, ticksEnabled, tickLowerBound);
    }
}
