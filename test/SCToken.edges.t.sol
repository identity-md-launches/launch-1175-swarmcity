// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, Vm} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SCToken} from "../src/SCToken.sol";

/// @dev Minimal stand-in for the launch factory: deploys through CREATE2 and holds the supply.
contract FactoryProbe {
    function deploy(bytes memory code, bytes32 salt) external returns (address deployed) {
        assembly ("memory-safe") {
            deployed := create2(0, add(code, 32), mload(code), salt)
        }
        require(deployed != address(0), "create2 failed");
    }
}

/// @notice Edge cases the main suite does not reach: who the deployer is, event counts, random
/// counterparties, per-transfer rounding of the cumulative tax, and the absence of any entry point
/// beyond plain ERC-20.
contract SCTokenEdgesTest is Test {
    SCToken internal token;
    address internal constant MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address internal constant CREATOR = 0xD30eA9E0FA0C671BB4dC6C6e83863396B1822951;
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    bytes32 internal constant TRANSFER_TOPIC = keccak256("Transfer(address,address,uint256)");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal spender = makeAddr("spender");

    function setUp() public {
        token = new SCToken();
    }

    // ---------------------------------------------------------------- deployment

    function test_SupplyGoesToWhoeverDeploysNotToAFixedAddress() public {
        address factory = makeAddr("factory");
        vm.prank(factory);
        SCToken fresh = new SCToken();
        assertEq(fresh.totalSupply(), SUPPLY);
        assertEq(fresh.balanceOf(factory), SUPPLY);
        assertEq(fresh.balanceOf(address(this)), 0);
        assertEq(fresh.balanceOf(CREATOR), 0);
        assertEq(fresh.balanceOf(MANAGER), 0);
        assertEq(fresh.INITIAL_SUPPLY(), fresh.totalSupply());
    }

    function test_Create2DeploymentByAFactoryContractMintsToTheFactory() public {
        FactoryProbe factory = new FactoryProbe();
        address predicted =
            vm.computeCreate2Address(bytes32(uint256(7)), keccak256(type(SCToken).creationCode), address(factory));
        address deployed = factory.deploy(type(SCToken).creationCode, bytes32(uint256(7)));
        assertEq(deployed, predicted);
        SCToken fresh = SCToken(deployed);
        assertEq(fresh.balanceOf(address(factory)), SUPPLY);
        assertEq(fresh.totalSupply(), SUPPLY);
        assertEq(fresh.name(), "SwarmCity");
        assertEq(fresh.symbol(), "SC");
        assertEq(fresh.decimals(), 18);
    }

    function test_TwoDeploymentsAreIndependentButShareTheSameConstants() public {
        SCToken other = new SCToken();
        assertEq(other.totalSupply(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(other.TAX_RECIPIENT(), token.TAX_RECIPIENT());
        assertEq(other.POOL_MANAGER(), token.POOL_MANAGER());
        assertEq(other.TAX_BPS(), token.TAX_BPS());
        token.transfer(alice, 1 ether);
        assertEq(other.balanceOf(alice), 0);
    }

    /// @dev The recipient and manager are compile-time constants: their 20 bytes are literally in
    /// the runtime code, and nothing in storage could redirect them.
    function test_TaxRecipientAndManagerAreCompiledIntoTheRuntime() public view {
        bytes memory runtime = address(token).code;
        assertTrue(_contains(runtime, _stripLeadingZeros(CREATOR)), "recipient not a literal in the code");
        assertTrue(_contains(runtime, _stripLeadingZeros(MANAGER)), "manager not a literal in the code");
    }

    function test_ConstantGettersSurviveTrading() public {
        token.transfer(MANAGER, 1_000 ether);
        vm.prank(MANAGER);
        token.transfer(alice, 1_000 ether);
        vm.prank(alice);
        token.transfer(MANAGER, 980 ether);
        assertEq(token.TAX_RECIPIENT(), CREATOR);
        assertEq(token.POOL_MANAGER(), MANAGER);
        assertEq(token.TAX_BPS(), 200);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    // ------------------------------------------------------------ entry points

    function test_NoReceiveOrFallbackAndNoEtherAccepted() public {
        vm.deal(address(this), 1 ether);
        (bool ok,) = address(token).call{value: 1 wei}("");
        assertFalse(ok, "plain ether transfer must fail");
        (ok,) = address(token).call{value: 1 wei}(abi.encodeWithSignature("transfer(address,uint256)", alice, 1));
        assertFalse(ok, "payable transfer must fail");
        (ok,) = address(token).call(hex"deadbeef");
        assertFalse(ok, "unknown selector must fail");
        (ok,) = address(token).call(hex"");
        assertFalse(ok, "empty calldata must fail");
        assertEq(address(token).balance, 0);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_MoreTaxSettersAndRescueFunctionsDoNotExist() public {
        string[14] memory signatures = [
            "renounceOwnership()",
            "setTaxWallet(address)",
            "setFees(uint256,uint256)",
            "setFee(uint256)",
            "excludeFromFee(address,bool)",
            "setExempt(address,bool)",
            "rescueTokens(address,uint256)",
            "withdraw()",
            "setSwapEnabled(bool)",
            "setMaxWallet(uint256)",
            "setMaxTx(uint256)",
            "enableTrading()",
            "increaseAllowance(address,uint256)",
            "permit(address,address,uint256,uint256,uint8,bytes32,bytes32)"
        ];
        address[3] memory callers = [address(this), CREATOR, MANAGER];
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], alice, true);
            for (uint256 c; c < callers.length; ++c) {
                vm.prank(callers[c]);
                (bool ok,) = address(token).call(data);
                assertFalse(ok, signatures[i]);
            }
        }
        assertEq(token.TAX_RECIPIENT(), CREATOR);
        assertEq(token.TAX_BPS(), 200);
    }

    function test_ApproveToOrFromZeroAddressReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(address(0));
        token.approve(alice, 1);
    }

    function test_StrangerCannotPullFromTheManagerWithoutAllowance() public {
        token.transfer(MANAGER, 100 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 100 ether));
        vm.prank(spender);
        token.transferFrom(MANAGER, spender, 100 ether);
        assertEq(token.balanceOf(MANAGER), 100 ether);
        assertEq(token.balanceOf(CREATOR), 0);
    }

    function test_TransferFromZeroAddressRevertsEvenForTheCreator() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        vm.prank(address(0));
        token.transfer(CREATOR, 1);
    }

    // ------------------------------------------------------------------ events

    function test_TaxedBuyEmitsExactlyTwoTransfersTaxFirst() public {
        token.transfer(MANAGER, 1_000);
        vm.recordLogs();
        vm.prank(MANAGER);
        token.transfer(alice, 1_000);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 2);
        _assertTransferLog(logs[0], MANAGER, CREATOR, 20);
        _assertTransferLog(logs[1], MANAGER, alice, 980);
    }

    function test_BuyBelowFiftyUnitsEmitsExactlyOneTransfer() public {
        token.transfer(MANAGER, 49);
        vm.recordLogs();
        vm.prank(MANAGER);
        token.transfer(alice, 49);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        _assertTransferLog(logs[0], MANAGER, alice, 49);
        assertEq(token.balanceOf(CREATOR), 0);
    }

    function test_UntaxedPathsEmitExactlyOneTransfer() public {
        token.transfer(alice, 100 ether);
        vm.recordLogs();
        vm.prank(alice);
        token.transfer(bob, 40 ether);
        vm.prank(bob);
        token.transfer(MANAGER, 40 ether);
        vm.prank(MANAGER);
        token.transfer(MANAGER, 40 ether);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 3);
        _assertTransferLog(logs[0], alice, bob, 40 ether);
        _assertTransferLog(logs[1], bob, MANAGER, 40 ether);
        _assertTransferLog(logs[2], MANAGER, MANAGER, 40 ether);
        assertEq(token.balanceOf(CREATOR), 0);
    }

    function test_DelegatedManagerSelfTransferIsUntaxedAndSpendsAllowance() public {
        token.transfer(MANAGER, 100 ether);
        vm.prank(MANAGER);
        token.approve(spender, 100 ether);
        vm.prank(spender);
        token.transferFrom(MANAGER, MANAGER, 100 ether);
        assertEq(token.balanceOf(MANAGER), 100 ether);
        assertEq(token.balanceOf(CREATOR), 0);
        assertEq(token.allowance(MANAGER, spender), 0);
    }

    function test_TaxRecipientCanSellAndBuyLikeAnyWallet() public {
        token.transfer(MANAGER, 100 ether);
        vm.prank(MANAGER);
        token.transfer(alice, 100 ether);
        assertEq(token.balanceOf(CREATOR), 2 ether);
        vm.prank(CREATOR);
        token.transfer(MANAGER, 2 ether);
        assertEq(token.balanceOf(CREATOR), 0);
        assertEq(token.balanceOf(MANAGER), 2 ether);
        vm.prank(MANAGER);
        token.transfer(CREATOR, 2 ether);
        assertEq(token.balanceOf(CREATOR), 2 ether, "buy by the recipient is credited gross");
        assertEq(token.balanceOf(MANAGER), 0);
    }

    // -------------------------------------------------------------------- fuzz

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_WalletToWalletIsNeverTaxedForAnyCounterparties(address from, address to, uint256 amount) public {
        vm.assume(from != MANAGER && to != MANAGER);
        vm.assume(from != address(0) && to != address(0));
        vm.assume(from != CREATOR && to != CREATOR);
        amount = bound(amount, 0, SUPPLY);
        token.transfer(from, amount);
        uint256 fromBefore = token.balanceOf(from);
        uint256 toBefore = token.balanceOf(to);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        if (from == to) {
            assertEq(token.balanceOf(from), fromBefore);
        } else {
            assertEq(token.balanceOf(from), fromBefore - amount);
            assertEq(token.balanceOf(to), toBefore + amount);
        }
        assertEq(token.balanceOf(CREATOR), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_SellFromAnyWalletArrivesWhole(address seller, uint256 amount, bool delegated) public {
        vm.assume(seller != MANAGER && seller != address(0) && seller != CREATOR);
        amount = bound(amount, 0, SUPPLY);
        token.transfer(seller, amount);
        uint256 sellerBefore = token.balanceOf(seller);
        if (delegated) {
            vm.prank(seller);
            token.approve(spender, amount);
            vm.prank(spender);
            assertTrue(token.transferFrom(seller, MANAGER, amount));
            assertEq(token.allowance(seller, spender), 0);
        } else {
            vm.prank(seller);
            assertTrue(token.transfer(MANAGER, amount));
        }
        assertEq(token.balanceOf(MANAGER), amount);
        assertEq(token.balanceOf(seller), sellerBefore - amount);
        assertEq(token.balanceOf(CREATOR), 0);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_BuyToAnyRecipientPaysFloorOfTwoPercent(address buyer, uint256 amount) public {
        vm.assume(buyer != MANAGER && buyer != address(0) && buyer != CREATOR);
        amount = bound(amount, 0, SUPPLY);
        token.transfer(MANAGER, amount);
        uint256 buyerBefore = token.balanceOf(buyer);
        vm.prank(MANAGER);
        assertTrue(token.transfer(buyer, amount));
        uint256 tax = amount / 50;
        assertEq(tax, amount * 200 / 10_000);
        assertLe(tax * 50, amount, "tax is rounded down");
        assertLt(amount - tax * 50, 50, "rounding loss is below one tax unit");
        assertEq(token.balanceOf(buyer) - buyerBefore, amount - tax);
        assertEq(token.balanceOf(CREATOR), tax);
        assertEq(token.balanceOf(MANAGER), 0);
        if (amount < 50) assertEq(tax, 0);
    }

    /// @dev Rounding happens per transfer: the recipient's cumulative balance is the sum of the
    /// per-buy floors, which is at most floor(2% of the total) and never more.
    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_CumulativeTaxIsSumOfPerBuyFloors(uint256[8] memory amounts) public {
        token.transfer(MANAGER, SUPPLY);
        uint256 expected;
        uint256 total;
        for (uint256 i; i < amounts.length; ++i) {
            uint256 amount = bound(amounts[i], 0, SUPPLY / amounts.length);
            address buyer = i % 2 == 0 ? alice : bob;
            vm.prank(MANAGER);
            token.transfer(buyer, amount);
            expected += amount / 50;
            total += amount;
            assertEq(token.balanceOf(CREATOR), expected, "cumulative tax drifted");
        }
        assertLe(expected, total / 50);
        assertGe(expected + amounts.length, total / 50, "per-buy rounding loses at most one unit each");
        assertEq(token.balanceOf(alice) + token.balanceOf(bob) + token.balanceOf(CREATOR), total);
        assertEq(token.balanceOf(MANAGER), SUPPLY - total);
        // The accumulated tax is ordinary spendable balance for the recipient.
        vm.prank(CREATOR);
        token.transfer(alice, expected);
        assertEq(token.balanceOf(CREATOR), 0);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_ManagerCannotSpendMoreThanGrossBalance(uint256 held, uint256 requested) public {
        held = bound(held, 0, SUPPLY - 1);
        requested = bound(requested, held + 1, SUPPLY);
        token.transfer(MANAGER, held);
        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientBalance.selector);
        vm.prank(MANAGER);
        token.transfer(alice, requested);
        assertEq(token.balanceOf(MANAGER), held);
        assertEq(token.balanceOf(CREATOR), 0);
        assertEq(token.balanceOf(alice), 0);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_RoundTripThroughManagerLosesExactlyTheTax(uint256 amount, uint8 rounds) public {
        amount = bound(amount, 0, SUPPLY);
        rounds = uint8(bound(rounds, 1, 8));
        token.transfer(MANAGER, amount);
        uint256 expectedTax;
        uint256 inPool = amount;
        for (uint256 i; i < rounds; ++i) {
            vm.prank(MANAGER);
            token.transfer(alice, inPool);
            expectedTax += inPool / 50;
            uint256 held = token.balanceOf(alice);
            assertEq(held, inPool - inPool / 50);
            vm.prank(alice);
            token.transfer(MANAGER, held);
            inPool = held;
        }
        assertEq(token.balanceOf(CREATOR), expectedTax);
        assertEq(token.balanceOf(MANAGER), amount - expectedTax);
        assertEq(token.balanceOf(alice), 0);
    }

    // ----------------------------------------------------------------- helpers

    function _assertTransferLog(Vm.Log memory log, address from, address to, uint256 value) internal pure {
        assertEq(log.topics.length, 3);
        assertEq(log.topics[0], TRANSFER_TOPIC);
        assertEq(address(uint160(uint256(log.topics[1]))), from);
        assertEq(address(uint160(uint256(log.topics[2]))), to);
        assertEq(abi.decode(log.data, (uint256)), value);
    }

    /// @dev The compiler emits an address literal with the shortest PUSH that fits it, so the
    /// manager's leading zero bytes are not in the code; match on the significant bytes.
    function _stripLeadingZeros(address value) internal pure returns (bytes memory out) {
        bytes memory full = abi.encodePacked(value);
        uint256 start;
        while (start < full.length - 1 && full[start] == 0) ++start;
        out = new bytes(full.length - start);
        for (uint256 i; i < out.length; ++i) {
            out[i] = full[start + i];
        }
    }

    function _contains(bytes memory haystack, bytes memory needle) internal pure returns (bool) {
        if (needle.length > haystack.length) return false;
        for (uint256 i; i + needle.length <= haystack.length; ++i) {
            bool matched = true;
            for (uint256 j; j < needle.length; ++j) {
                if (haystack[i + j] != needle[j]) {
                    matched = false;
                    break;
                }
            }
            if (matched) return true;
        }
        return false;
    }
}
