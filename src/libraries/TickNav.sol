// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.30;

import {TickBitmap} from "./TickBitmap.sol";

library TickNav {
    using TickBitmap for TickBitmap.Bitmap;

    enum TickMode {
        Interior,
        Boundary
    }

    struct Tick {
        uint128 m;
        TickMode mode;
        bool set;
        uint128 r;
        int128 k;
        uint128 s;
    }

    uint256 constant TICK_OFFSET = 1 << 31;

    function fromIndex(uint256 index_) internal pure returns (int32) {
        int256 signed = int256(index_) - int256(uint256(TICK_OFFSET));
        return int32(signed);
    }

    function toIndex(int32 tick_) internal pure returns (uint256) {
        int256 shifted = int256(tick_) + int256(uint256(TICK_OFFSET));
        return uint256(uint32(uint256(shifted)));
    }

    function nextUp(TickBitmap.Bitmap storage bm_, int32 from_) internal view returns (int32, bool) {
        uint256 indexFrom = toIndex(from_) + 1;
        uint256 indexMax = type(uint32).max;
        uint256 index = bm_.nextSet(indexFrom, indexMax);
        if (index == TickBitmap.NOT_FOUND) {
            return (0, false);
        }

        int256 signed = int256(index) - int256(TICK_OFFSET);
        return (int32(signed), true);
    }

    function nextDown(TickBitmap.Bitmap storage bm_, int32 from_, bool ticksEnabled_, uint256 tickLowerBound_)
        internal
        view
        returns (int32, bool)
    {
        uint256 indexFrom = toIndex(from_);
        indexFrom = indexFrom == 0 ? 0 : (indexFrom - 1);
        uint256 indexMin = ticksEnabled_ ? tickLowerBound_ : 0;
        if (indexFrom < indexMin) {
            return (0, false);
        }

        uint256 index = bm_.prevSet(indexFrom, indexMin);
        if (index == TickBitmap.NOT_FOUND) {
            return (0, false);
        }

        int256 signed = int256(index) - int256(TICK_OFFSET);
        return (int32(signed), true);
    }
}
