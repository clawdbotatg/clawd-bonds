// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Mock CLAWD token for local testing only
contract MockCLAWD is ERC20 {
    constructor(address recipient) ERC20("CLAWD", "CLAWD") {
        _mint(recipient, 1_000_000_000e18);
    }
}
