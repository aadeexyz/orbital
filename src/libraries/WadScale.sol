// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.30;

library WadScale {
    function computeScale64(uint8 decimals_) internal pure returns (bool, uint64) {
        bool up;
        uint64 factor;
        if (decimals_ <= 18) {
            up = true;
            factor = uint64(10 ** uint256(18 - decimals_));
        } else {
            up = false;
            factor = uint64(10 ** uint256(decimals_ - 18));
        }

        return (up, factor);
    }

    function toWad(uint256 raw_, bool scaleUp_, uint256 factor_) internal pure returns (uint256) {
        return scaleUp_ ? raw_ * factor_ : raw_ / factor_;
    }

    function fromWad(uint256 wad_, bool scaleUp_, uint256 factor_) internal pure returns (uint256) {
        return scaleUp_ ? wad_ / factor_ : wad_ * factor_;
    }

    function toWadSafe(uint256 raw_, bool scaleUp_, uint64 factor_) internal pure returns (bool, uint256) {
        if (scaleUp_) {
            if (raw_ != 0 && raw_ > type(uint256).max / uint256(factor_)) {
                return (false, 0);
            }
            return (true, raw_ * uint256(factor_));
        }

        return (true, raw_ / uint256(factor_));
    }
}
