// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SCToken} from "../src/SCToken.sol";

contract SCTokenTest is Test {
    SCToken internal token;
    address internal constant MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address internal constant CREATOR = 0xD30eA9E0FA0C671BB4dC6C6e83863396B1822951;
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal spender = makeAddr("spender");

    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        token = new SCToken();
    }

    function test_DeploymentMintsEntireFixedSupplyOnlyToDeployer() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(MANAGER), 0);
        assertEq(token.balanceOf(CREATOR), 0);
        assertEq(token.name(), "SwarmCity");
        assertEq(token.symbol(), "SC");
        assertEq(token.decimals(), 18);
        assertEq(token.TAX_RECIPIENT(), CREATOR);
        assertEq(token.TAX_BPS(), 200);
        assertEq(token.POOL_MANAGER(), MANAGER);
    }

    function test_FactorySwarmDistributionClaimAndPoolSeedArriveWhole() public {
        address distributor = makeAddr("distributor");
        token.transfer(distributor, SUPPLY / 10);
        assertEq(token.balanceOf(distributor), SUPPLY / 10);
        vm.prank(distributor);
        token.transfer(alice, SUPPLY / 10);
        token.transfer(MANAGER, SUPPLY * 9 / 10);
        assertEq(token.balanceOf(alice), SUPPLY / 10);
        assertEq(token.balanceOf(MANAGER), SUPPLY * 9 / 10);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(distributor), 0);
        assertEq(token.balanceOf(CREATOR), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_WalletTransfersAndSelfTransfersAreUntaxed() public {
        token.transfer(alice, 100 ether);
        vm.startPrank(alice);
        token.transfer(alice, 100 ether);
        token.transfer(bob, 100 ether);
        vm.stopPrank();
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 100 ether);
        assertEq(token.balanceOf(CREATOR), 0);
    }

    function test_BuyDebitsGrossAndEmitsTaxAndNetTransfers() public {
        token.transfer(MANAGER, 100 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(MANAGER, CREATOR, 2 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(MANAGER, alice, 98 ether);
        vm.prank(MANAGER);
        assertTrue(token.transfer(alice, 100 ether));
        assertEq(token.balanceOf(MANAGER), 0);
        assertEq(token.balanceOf(CREATOR), 2 ether);
        assertEq(token.balanceOf(alice), 98 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SellAndPoolManagerSelfTransferAreUntaxed() public {
        token.transfer(alice, 100 ether);
        vm.prank(alice);
        token.transfer(MANAGER, 100 ether);
        vm.prank(MANAGER);
        token.transfer(MANAGER, 100 ether);
        assertEq(token.balanceOf(MANAGER), 100 ether);
        assertEq(token.balanceOf(CREATOR), 0);
    }

    function test_TaxAccumulatesWithPerTransferRounding() public {
        token.transfer(MANAGER, 300);
        vm.startPrank(MANAGER);
        token.transfer(alice, 49);
        assertEq(token.balanceOf(CREATOR), 0);
        token.transfer(alice, 50);
        assertEq(token.balanceOf(CREATOR), 1);
        token.transfer(bob, 101);
        assertEq(token.balanceOf(CREATOR), 3);
        token.transfer(bob, 100);
        vm.stopPrank();
        assertEq(token.balanceOf(CREATOR), 5);
        assertEq(token.balanceOf(alice), 98);
        assertEq(token.balanceOf(bob), 197);
        assertEq(token.balanceOf(MANAGER), 0);
    }

    function test_ZeroBuyEmitsTransferWithoutTax() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(MANAGER, alice, 0);
        vm.prank(MANAGER);
        assertTrue(token.transfer(alice, 0));
        assertEq(token.balanceOf(CREATOR), 0);
    }

    function test_BuyToCreatorCreditsGrossWithoutDoubleTax() public {
        token.transfer(MANAGER, 100 ether);
        vm.prank(MANAGER);
        token.transfer(CREATOR, 100 ether);
        assertEq(token.balanceOf(MANAGER), 0);
        assertEq(token.balanceOf(CREATOR), 100 ether);
        vm.prank(CREATOR);
        token.transfer(alice, 100 ether);
        assertEq(token.balanceOf(alice), 100 ether);
    }

    function test_TransferFromBuyUsesGrossAllowance() public {
        token.transfer(MANAGER, 100 ether);
        vm.prank(MANAGER);
        token.approve(spender, 100 ether);
        vm.prank(spender);
        token.transferFrom(MANAGER, alice, 100 ether);
        assertEq(token.allowance(MANAGER, spender), 0);
        assertEq(token.balanceOf(alice), 98 ether);
        assertEq(token.balanceOf(CREATOR), 2 ether);
    }

    function test_NetOnlyAllowanceCannotSpendGrossAndDoesNotMoveTax() public {
        token.transfer(MANAGER, 100 ether);
        vm.prank(MANAGER);
        token.approve(spender, 98 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 98 ether, 100 ether)
        );
        vm.prank(spender);
        token.transferFrom(MANAGER, alice, 100 ether);
        assertEq(token.balanceOf(CREATOR), 0);
        assertEq(token.balanceOf(MANAGER), 100 ether);
        assertEq(token.allowance(MANAGER, spender), 98 ether);
    }

    function test_InfiniteAllowanceAndDelegatedSell() public {
        token.transfer(alice, 100 ether);
        vm.prank(alice);
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        token.transferFrom(alice, MANAGER, 100 ether);
        assertEq(token.allowance(alice, spender), type(uint256).max);
        assertEq(token.balanceOf(MANAGER), 100 ether);
        assertEq(token.balanceOf(CREATOR), 0);
    }

    function test_PoolManagerAsSpenderDoesNotTaxAnOrdinaryWallet() public {
        token.transfer(alice, 100 ether);
        vm.prank(alice);
        token.approve(MANAGER, 100 ether);
        vm.prank(MANAGER);
        token.transferFrom(alice, bob, 100 ether);
        assertEq(token.balanceOf(bob), 100 ether);
        assertEq(token.balanceOf(CREATOR), 0);
    }

    function test_InsufficientGrossBalanceRollsBackTaxAndAllowance() public {
        token.transfer(MANAGER, 99 ether);
        vm.prank(MANAGER);
        token.approve(spender, 100 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, MANAGER, 97 ether, 98 ether)
        );
        vm.prank(spender);
        token.transferFrom(MANAGER, alice, 100 ether);
        assertEq(token.balanceOf(MANAGER), 99 ether);
        assertEq(token.balanceOf(CREATOR), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(MANAGER, spender), 100 ether);
    }

    function test_MaxUintBuyRevertsWithoutArithmeticOverflowOrStateChange() public {
        token.transfer(MANAGER, 100 ether);
        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientBalance.selector);
        vm.prank(MANAGER);
        token.transfer(alice, type(uint256).max);
        assertEq(token.balanceOf(MANAGER), 100 ether);
        assertEq(token.balanceOf(CREATOR), 0);
    }

    function test_CannotBurnThroughZeroAddress() public {
        token.transfer(MANAGER, 100 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(MANAGER);
        token.transfer(address(0), 100 ether);
        assertEq(token.balanceOf(MANAGER), 100 ether);
        assertEq(token.balanceOf(CREATOR), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_NoAdminMintBurnOrOwnershipEntryPoints() public {
        bytes[] memory calls = new bytes[](16);
        calls[0] = abi.encodeWithSignature("owner()");
        calls[1] = abi.encodeWithSignature("transferOwnership(address)", alice);
        calls[2] = abi.encodeWithSignature("mint(address,uint256)", alice, 1);
        calls[3] = abi.encodeWithSignature("burn(uint256)", 1);
        calls[4] = abi.encodeWithSignature("burnFrom(address,uint256)", alice, 1);
        calls[5] = abi.encodeWithSignature("pause()");
        calls[6] = abi.encodeWithSignature("blacklist(address)", alice);
        calls[7] = abi.encodeWithSignature("setTaxRate(uint256)", 0);
        calls[8] = abi.encodeWithSignature("setTaxRecipient(address)", alice);
        calls[9] = abi.encodeWithSignature("setPoolManager(address)", alice);
        calls[10] = abi.encodeWithSignature("upgradeTo(address)", alice);
        calls[11] = abi.encodeWithSignature("initialize(address)", alice);
        calls[12] = abi.encodeWithSignature("seize(address)", alice);
        calls[13] = abi.encodeWithSignature("freeze(address)", alice);
        calls[14] = abi.encodeWithSignature("grantRole(bytes32,address)", bytes32(0), alice);
        calls[15] = abi.encodeWithSignature("setMinter(address)", alice);
        token.transfer(alice, 100 ether);
        for (uint256 i; i < calls.length; ++i) {
            (bool deployerOk,) = address(token).call(calls[i]);
            assertFalse(deployerOk);
            vm.prank(bob);
            (bool strangerOk,) = address(token).call(calls[i]);
            assertFalse(strangerOk);
        }
        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientAllowance.selector);
        token.transferFrom(alice, address(this), 1);
        vm.prank(alice);
        token.transfer(bob, 100 ether);
        assertEq(token.balanceOf(bob), 100 ether);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.TAX_RECIPIENT(), CREATOR);
        assertEq(token.TAX_BPS(), 200);
    }

    function test_RuntimeHasNoForbiddenOpcodes() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
            } else {
                assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff);
            }
        }
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_BuyConservesSupplyAndChargesTwoPercent(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        token.transfer(MANAGER, amount);
        vm.prank(MANAGER);
        token.transfer(alice, amount);
        uint256 fee = amount * 2 / 100;
        assertEq(token.balanceOf(alice), amount - fee);
        assertEq(token.balanceOf(CREATOR), fee);
        assertEq(token.balanceOf(MANAGER), 0);
        assertEq(token.balanceOf(address(this)) + token.balanceOf(alice) + token.balanceOf(CREATOR), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_BuyThenSellOnlyLosesCreatorTax(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        token.transfer(MANAGER, amount);
        vm.prank(MANAGER);
        token.transfer(alice, amount);
        uint256 bought = token.balanceOf(alice);
        vm.prank(alice);
        token.transfer(MANAGER, bought);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(MANAGER), bought);
        assertEq(token.balanceOf(MANAGER) + token.balanceOf(CREATOR), amount);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_DelegatedBuysPreserveInfiniteAllowance(uint256 first, uint256 second) public {
        first = bound(first, 0, SUPPLY);
        second = bound(second, 0, SUPPLY - first);
        token.transfer(MANAGER, SUPPLY);
        vm.prank(MANAGER);
        token.approve(spender, type(uint256).max);
        vm.startPrank(spender);
        token.transferFrom(MANAGER, alice, first);
        token.transferFrom(MANAGER, bob, second);
        vm.stopPrank();
        assertEq(token.allowance(MANAGER, spender), type(uint256).max);
        assertEq(token.balanceOf(CREATOR), first * 2 / 100 + second * 2 / 100);
        assertEq(token.balanceOf(MANAGER), SUPPLY - first - second);
        assertEq(token.balanceOf(alice) + token.balanceOf(bob) + token.balanceOf(CREATOR), first + second);
    }
}
