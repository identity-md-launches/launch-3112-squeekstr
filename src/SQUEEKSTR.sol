// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title SQUEEKSTR
/// @notice Fixed-supply ERC-20 for sqkstr.xyz: one billion SQKSTR with 18 decimals.
/// @dev The immediate deployer receives the entire supply. There are no administrative powers
///      or externally callable mint/burn paths. In a factory launch, the factory is the deployer.
contract SQUEEKSTR is ERC20 {
    /// @notice Total issuance in the token's smallest units (10^27).
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20("SQUEEKSTR", "SQKSTR") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
