// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title SwarmCity
/// @notice Fixed-supply ERC-20 with a permanent 2% tax on PoolManager outflows.
/// @dev The launch factory receives the entire supply as deployer and handles distribution.
contract SCToken is ERC20 {
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;
    address public constant POOL_MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address public constant TAX_RECIPIENT = 0xD30eA9E0FA0C671BB4dC6C6e83863396B1822951;
    uint256 public constant TAX_BPS = 200;
    uint256 private constant BPS_DENOMINATOR = 10_000;

    constructor() ERC20("SwarmCity", "SC") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }

    /// @dev All transfers into the manager are exempt, including manager self-transfers.
    /// The gross amount leaves the manager; the recipient receives gross minus the tax.
    /// This applies equally to transfer and transferFrom, regardless of the spender.
    function _update(address from, address to, uint256 value) internal override {
        if (from == POOL_MANAGER && to != POOL_MANAGER) {
            // For the fixed 200 bps rate, dividing by 50 is exactly floor(value * 2 / 100)
            // and cannot overflow even when a caller supplies an invalid oversized amount.
            uint256 tax = value / (BPS_DENOMINATOR / TAX_BPS);
            if (tax != 0) {
                super._update(from, TAX_RECIPIENT, tax);
                value -= tax;
            }
        }
        super._update(from, to, value);
    }
}
