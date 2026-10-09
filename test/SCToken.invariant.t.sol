// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {SCToken} from "../src/SCToken.sol";

contract SCTokenHandler is Test {
    SCToken public immutable token;
    address[5] public actors;
    uint256 public cumulativeTax;

    constructor(SCToken token_) {
        token = token_;
        actors = [address(this), makeAddr("alice"), makeAddr("bob"), makeAddr("carol"), token_.POOL_MANAGER()];
    }

    function move(uint256 fromSeed, uint256 toSeed, uint256 amount, bool delegated) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, token.balanceOf(from));
        if (from == token.POOL_MANAGER() && to != from) {
            cumulativeTax += amount * 2 / 100;
        }
        if (delegated) {
            vm.prank(from);
            token.approve(address(this), amount);
            token.transferFrom(from, to, amount);
            assertEq(token.allowance(from, address(this)), 0);
        } else {
            vm.prank(from);
            token.transfer(to, amount);
        }
    }
}

contract SCTokenInvariantTest is StdInvariant, Test {
    SCToken internal token;
    SCTokenHandler internal handler;

    function setUp() public {
        token = new SCToken();
        handler = new SCTokenHandler(token);
        token.transfer(address(handler), token.totalSupply());
        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = SCTokenHandler.move.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_SupplyIsFixedAndAllBalancesAreConserved() public view {
        uint256 held = token.balanceOf(token.TAX_RECIPIENT());
        for (uint256 i; i < 5; ++i) {
            held += token.balanceOf(handler.actors(i));
        }
        assertEq(held, 1_000_000_000 ether);
        assertEq(token.totalSupply(), 1_000_000_000 ether);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(token.TAX_RECIPIENT()), handler.cumulativeTax());
        assertEq(token.TAX_BPS(), 200);
    }
}
