// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {BaseAdapter, Errors, IPriceOracle} from "../imports/BaseAdapter.sol";

/// @title FixedRateOracle (Always returns 1:1 rate)
/// @notice PriceOracle adapter that always returns a fixed 1:1 exchange rate.
contract FixedRateOracle is BaseAdapter {
    /// @inheritdoc IPriceOracle
    string public constant name = "FixedRateOracle";
    /// @notice The address of the base asset.
    address public immutable base;
    /// @notice The address of the quote asset.
    address public immutable quote;

    /// @notice Deploy a FixedRateOracle.
    /// @param _base The address of the base asset.
    /// @param _quote The address of the quote asset.
    constructor(address _base, address _quote) {
        base = _base;
        quote = _quote;
    }

    /// @notice Get a quote by always returning the input amount (1:1 conversion rate).
    /// @param inAmount The amount of `base` to convert.
    /// @param _base The token that is being priced.
    /// @param _quote The token that is the unit of account.
    /// @return The same amount as `inAmount` (1:1 conversion).
    function _getQuote(uint256 inAmount, address _base, address _quote) internal view override returns (uint256) {
        require((_base == base && _quote == quote) || (_base == quote && _quote == base), "Invalid token pair");
        return inAmount; // 1:1 rate, return the input amount unchanged
    }
}
