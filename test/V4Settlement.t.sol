// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {ModifyLiquidityParams, SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {SCToken} from "../src/SCToken.sol";

/// @dev Offline pair-token fixture only; never included in launch.json.
contract IMDTestToken is ERC20 {
    constructor() ERC20("IMD test fixture", "IMD") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @notice Exercises the actual v4 manager implementation locally at its mainnet address.
/// @dev Acts as the factory for deployment/seeding and as a trader during swaps.
contract V4SettlementTest is Test, IUnlockCallback {
    address internal constant MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address internal constant PAIRED = address(bytes20(hex"d34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7"));
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    uint256 internal constant Q96 = 1 << 96;
    IPoolManager internal manager = IPoolManager(MANAGER);
    IMDTestToken internal pair = IMDTestToken(PAIRED);
    SCToken internal token;
    PoolKey internal key;

    function setUp() public {
        // Run the constructor at the canonical address so v4's immutable original address matches.
        vm.etch(MANAGER, abi.encodePacked(type(PoolManager).creationCode, abi.encode(address(this))));
        (bool ok, bytes memory runtime) = MANAGER.call("");
        assertTrue(ok);
        assertGt(runtime.length, 0);
        vm.etch(MANAGER, runtime);
        vm.etch(PAIRED, address(new IMDTestToken()).code);
    }

    function test_SeedBuyAndSellWithSCAsCurrency0() public {
        _launchAndTrade(true);
    }

    function test_SeedBuyAndSellWithSCAsCurrency1() public {
        _launchAndTrade(false);
    }

    function _launchAndTrade(bool tokenIsZero) internal {
        // CREATE addresses vary; exercise both real address orderings without modifying SC code.
        bool found;
        for (uint256 i; i < 256; ++i) {
            token = new SCToken();
            if ((address(token) < PAIRED) == tokenIsZero) {
                found = true;
                break;
            }
        }
        assertTrue(found, "could not construct requested currency order");
        assertEq(token.balanceOf(address(this)), SUPPLY);
        address distributor = makeAddr("launch distributor");
        token.transfer(distributor, SUPPLY / 10);
        vm.prank(distributor);
        token.transfer(makeAddr("swarm claimant"), SUPPLY / 10);

        key = PoolKey({
            currency0: Currency.wrap(tokenIsZero ? address(token) : PAIRED),
            currency1: Currency.wrap(tokenIsZero ? PAIRED : address(token)),
            fee: 12500,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
        _seed(tokenIsZero);

        uint256 budget = SUPPLY * 9 / 10;
        uint256 seeded = token.balanceOf(MANAGER);
        assertGt(seeded, 0);
        assertLe(seeded, budget);
        assertLe(budget - seeded, 1000, "only rounding dust may remain");
        assertEq(token.balanceOf(token.TAX_RECIPIENT()), 0, "seed must be tax free");
        assertEq(pair.balanceOf(MANAGER), 0, "seed must be single sided");
        _trade(tokenIsZero, seeded);
    }

    function _seed(bool tokenIsZero) internal {
        // 2,500 IMD / 1,000,000,000 SC = 1 / 400,000; invert when SC is currency1.
        uint256 priceX192 = tokenIsZero ? (uint256(1) << 192) / 400_000 : (uint256(1) << 192) * 400_000;
        uint160 opening = uint160(_sqrt(priceX192));
        int24 tick = manager.initialize(key, opening);
        int24 aligned = tick / 60 * 60;
        if (tick < 0 && tick % 60 != 0) aligned -= 60;
        int24 lower = tokenIsZero ? aligned + 60 : int24(-887220);
        int24 upper = tokenIsZero ? int24(887220) : aligned;
        uint160 sqrtA = TickMath.getSqrtPriceAtTick(lower);
        uint160 sqrtB = TickMath.getSqrtPriceAtTick(upper);
        uint256 budget = SUPPLY * 9 / 10;
        uint256 liquidity = tokenIsZero
            ? FullMath.mulDiv(budget, FullMath.mulDiv(sqrtA, sqrtB, Q96), sqrtB - sqrtA)
            : FullMath.mulDiv(budget, Q96, sqrtB - sqrtA);
        assertLe(liquidity, uint256(uint128(type(int128).max)));
        manager.unlock(
            abi.encode(false, abi.encode(ModifyLiquidityParams(lower, upper, int256(liquidity), bytes32(0))))
        );
    }

    function _trade(bool tokenIsZero, uint256 seeded) internal {
        uint256 remainder = token.balanceOf(address(this));
        pair.mint(address(this), 10 ether);

        BalanceDelta buy = _swap(!tokenIsZero, -int256(0.01 ether));
        int128 scDelta = tokenIsZero ? buy.amount0() : buy.amount1();
        assertGt(int256(scDelta), 0);
        uint256 gross = uint256(int256(scDelta));
        uint256 tax = gross * 2 / 100;
        uint256 bought = token.balanceOf(address(this)) - remainder;
        assertGt(bought, 0);
        assertEq(bought, gross - tax);
        assertEq(token.balanceOf(token.TAX_RECIPIENT()), tax);
        assertEq(token.balanceOf(MANAGER), seeded - gross);

        uint256 pairBeforeSale = pair.balanceOf(address(this));
        _swap(tokenIsZero, -int256(bought));
        assertGt(pair.balanceOf(address(this)), pairBeforeSale);
        assertEq(token.balanceOf(address(this)), remainder, "all bought SC must be sellable");
        assertEq(token.balanceOf(MANAGER), seeded - tax, "sale must settle its entire SC input");
        assertEq(token.balanceOf(token.TAX_RECIPIENT()), tax, "sale must not charge a second tax");
        assertEq(token.totalSupply(), SUPPLY);
    }

    function _swap(bool zeroForOne, int256 amount) internal returns (BalanceDelta) {
        uint160 limit = zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;
        return
            abi.decode(
                manager.unlock(abi.encode(true, abi.encode(SwapParams(zeroForOne, amount, limit)))), (BalanceDelta)
            );
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == MANAGER, "only manager");
        (bool swapAction, bytes memory parameters) = abi.decode(data, (bool, bytes));
        BalanceDelta delta;
        if (swapAction) {
            delta = manager.swap(key, abi.decode(parameters, (SwapParams)), "");
        } else {
            (delta,) = manager.modifyLiquidity(key, abi.decode(parameters, (ModifyLiquidityParams)), "");
        }
        _settle(key.currency0, delta.amount0());
        _settle(key.currency1, delta.amount1());
        return abi.encode(delta);
    }

    function _settle(Currency currency, int128 delta) internal {
        if (delta < 0) {
            uint256 owed = uint256(-int256(delta));
            manager.sync(currency);
            assertTrue(IERC20(Currency.unwrap(currency)).transfer(MANAGER, owed));
            assertEq(manager.settle(), owed, "PoolManager input arrived short");
        } else if (delta > 0) {
            manager.take(currency, address(this), uint256(int256(delta)));
        }
    }

    function _sqrt(uint256 x) internal pure returns (uint256 y) {
        y = x;
        uint256 z = (x + 1) / 2;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
}
