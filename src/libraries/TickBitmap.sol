// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.30;

import {LibBit} from "solady/utils/LibBit.sol";

library TickBitmap {
    using LibBit for uint256;

    struct Bitmap {
        mapping(uint256 => uint256) words;
        mapping(uint256 => uint256) meta;
    }

    uint256 internal constant NOT_FOUND = type(uint256).max;

    function _wordIndex(uint256 index_) private pure returns (uint256) {
        return index_ >> 8;
    }

    function _bitPos(uint256 index_) private pure returns (uint256) {
        return index_ & 0xff;
    }

    function _superIndex(uint256 wordIndex_) private pure returns (uint256) {
        return wordIndex_ >> 8;
    }

    function _superBit(uint256 wordIndex_) private pure returns (uint256) {
        return wordIndex_ & 0xff;
    }

    function get(Bitmap storage bm_, uint256 index_) internal view returns (bool) {
        return (bm_.words[_wordIndex(index_)] >> _bitPos(index_)) & 1 == 1;
    }

    function set(Bitmap storage bm_, uint256 index_) internal {
        uint256 wIdx = _wordIndex(index_);
        uint256 mask = uint256(1) << _bitPos(index_);
        uint256 w = bm_.words[wIdx];
        if (w & mask != 0) return;
        unchecked {
            w |= mask;
            bm_.words[wIdx] = w;
            if (w == mask) {
                uint256 sIdx = _superIndex(wIdx);
                bm_.meta[sIdx] |= (uint256(1) << _superBit(wIdx));
            }
        }
    }

    function unset(Bitmap storage bm_, uint256 index_) internal {
        uint256 wIdx = _wordIndex(index_);
        uint256 mask = uint256(1) << _bitPos(index_);
        uint256 w = bm_.words[wIdx];
        if (w & mask == 0) return;
        unchecked {
            w &= ~mask;
            bm_.words[wIdx] = w;
            if (w == 0) {
                uint256 sIdx = _superIndex(wIdx);
                bm_.meta[sIdx] &= ~(uint256(1) << _superBit(wIdx));
            }
        }
    }

    function nextSet(Bitmap storage bm_, uint256 from, uint256 upTo) internal view returns (uint256) {
        if (from > upTo) return NOT_FOUND;

        uint256 wIdx = _wordIndex(from);
        uint256 pos = _bitPos(from);

        {
            uint256 w = bm_.words[wIdx] & (~uint256(0) << pos);
            if (w != 0) {
                uint256 bit = LibBit.ffs(w);
                uint256 idx = (wIdx << 8) | bit;
                return idx <= upTo ? idx : NOT_FOUND;
            }
        }

        uint256 sIdx = _superIndex(wIdx);
        uint256 sPos = _superBit(wIdx);

        {
            uint256 mw = bm_.meta[sIdx] & (~uint256(0) << sPos);
            mw = mw & ~(uint256(1) << sPos);
            if (mw != 0) {
                uint256 nextWordInSame = (sIdx << 8) | LibBit.ffs(mw);
                uint256 w = bm_.words[nextWordInSame];
                uint256 bit = LibBit.ffs(w);
                uint256 idx = (nextWordInSame << 8) | bit;
                return idx <= upTo ? idx : NOT_FOUND;
            }
        }

        uint256 lastWord = _wordIndex(upTo);
        uint256 lastSuper = _superIndex(lastWord);
        for (uint256 si = sIdx + 1; si <= lastSuper; ++si) {
            uint256 mw = bm_.meta[si];
            if (mw == 0) continue;
            uint256 wInGroup = LibBit.ffs(mw);
            uint256 wIdx2 = (si << 8) | wInGroup;
            if (wIdx2 > lastWord) break;
            uint256 w = bm_.words[wIdx2];
            uint256 bit = LibBit.ffs(w);
            uint256 idx = (wIdx2 << 8) | bit;
            if (idx <= upTo) return idx;
            break;
        }
        return NOT_FOUND;
    }

    function prevSet(Bitmap storage bm_, uint256 from_, uint256 downTo_) internal view returns (uint256) {
        if (from_ < downTo_) return NOT_FOUND;

        uint256 wIdx = _wordIndex(from_);
        uint256 pos = _bitPos(from_);

        {
            uint256 mask = (pos == 255) ? type(uint256).max : ((uint256(1) << (pos + 1)) - 1);
            uint256 w = bm_.words[wIdx] & mask;
            if (w != 0) {
                uint256 bit = LibBit.fls(w);
                uint256 idx = (wIdx << 8) | bit;
                return idx >= downTo_ ? idx : NOT_FOUND;
            }
        }

        uint256 sIdx = _superIndex(wIdx);
        uint256 firstWord = _wordIndex(downTo_);
        uint256 firstSuper = _superIndex(firstWord);
        if (sIdx > firstSuper) {
            uint256 si = sIdx - 1;
            while (true) {
                uint256 mw = bm_.meta[si];
                if (mw != 0) {
                    uint256 wInGroup = LibBit.fls(mw);
                    uint256 wIdx2 = (si << 8) | wInGroup;
                    if (wIdx2 < firstWord) break;
                    uint256 w = bm_.words[wIdx2];
                    uint256 bit = LibBit.fls(w);
                    uint256 idx = (wIdx2 << 8) | bit;
                    if (idx >= downTo_) return idx;
                }
                if (si == firstSuper) break;
                unchecked {
                    si--;
                }
            }
        }
        return NOT_FOUND;
    }
}
