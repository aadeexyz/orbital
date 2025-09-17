// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.30;

import {TickBitmap} from "../../../src/libraries/TickBitmap.sol";

contract TickBitmapHarness {
    using TickBitmap for TickBitmap.Bitmap;

    TickBitmap.Bitmap internal bm;

    function set(uint256 i) external {
        bm.set(i);
    }

    function unset(uint256 i) external {
        bm.unset(i);
    }

    function get(uint256 i) external view returns (bool) {
        return bm.get(i);
    }

    function nextSet(uint256 from, uint256 upTo) external view returns (uint256) {
        return bm.nextSet(from, upTo);
    }

    function prevSet(uint256 from, uint256 downTo) external view returns (uint256) {
        return bm.prevSet(from, downTo);
    }

    function wordAt(uint256 wIdx) external view returns (uint256) {
        return bm.words[wIdx];
    }

    function metaAt(uint256 sIdx) external view returns (uint256) {
        return bm.meta[sIdx];
    }
}
