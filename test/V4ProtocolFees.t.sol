// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
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

/// @dev Offline IMD stand-in; never part of launch.json.
contract PairFixture is ERC20 {
    constructor() ERC20("IMD fixture", "IMD") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @notice Shared launch fixture: the real vendored PoolManager built at its mainnet address with
/// the test as its owner, an ERC-20 IMD at the paired address, SC seeded single-sided with 90% of
/// the supply at the 2,500 IMD opening cap, the 1.25% LP fee and the maximum protocol fee switched
/// on in both directions. The deriving contract acts as the factory and liquidity provider.
abstract contract V4FeeFixture is Test, IUnlockCallback {
    address internal constant MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address internal constant PAIRED = address(bytes20(hex"d34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7"));
    address internal constant CREATOR = 0xD30eA9E0FA0C671BB4dC6C6e83863396B1822951;
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    uint256 internal constant Q96 = 1 << 96;
    uint24 internal constant MAX_PROTOCOL_FEE_BOTH_WAYS = (uint24(1000) << 12) | 1000;

    IPoolManager internal manager = IPoolManager(MANAGER);
    PairFixture internal pair = PairFixture(PAIRED);
    SCToken internal token;
    PoolKey internal key;
    bool internal tokenIsZero;
    int24 internal lowerTick;
    int24 internal upperTick;
    uint256 internal seededLiquidity;
    uint256 internal seeded;

    function _deployFixture() internal {
        vm.etch(MANAGER, abi.encodePacked(type(PoolManager).creationCode, abi.encode(address(this))));
        (bool ok, bytes memory runtime) = MANAGER.call("");
        require(ok && runtime.length > 0, "manager build failed");
        vm.etch(MANAGER, runtime);
        vm.etch(PAIRED, address(new PairFixture()).code);

        token = new SCToken();
        tokenIsZero = address(token) < PAIRED;
        key = PoolKey({
            currency0: Currency.wrap(tokenIsZero ? address(token) : PAIRED),
            currency1: Currency.wrap(tokenIsZero ? PAIRED : address(token)),
            fee: 12500,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        // Factory flows: the swarm's tenth leaves whole, then the pool is seeded from the rest.
        address distributor = makeAddr("distributor");
        token.transfer(distributor, SUPPLY / 10);
        _seed();
        seeded = token.balanceOf(MANAGER);
        require(seeded > 0 && seeded <= SUPPLY * 9 / 10, "seed out of budget");
        require(token.balanceOf(CREATOR) == 0, "seed was taxed");

        // Protocol fees on, at the maximum v4 permits, in both directions.
        manager.setProtocolFeeController(address(this));
        manager.setProtocolFee(key, MAX_PROTOCOL_FEE_BOTH_WAYS);
    }

    function _seed() internal {
        uint256 priceX192 = tokenIsZero ? (uint256(1) << 192) / 400_000 : (uint256(1) << 192) * 400_000;
        int24 tick = manager.initialize(key, uint160(_sqrt(priceX192)));
        int24 aligned = tick / 60 * 60;
        if (tick < 0 && tick % 60 != 0) aligned -= 60;
        lowerTick = tokenIsZero ? aligned + 60 : int24(-887220);
        upperTick = tokenIsZero ? int24(887220) : aligned;
        uint160 sqrtA = TickMath.getSqrtPriceAtTick(lowerTick);
        uint160 sqrtB = TickMath.getSqrtPriceAtTick(upperTick);
        uint256 budget = SUPPLY * 9 / 10;
        seededLiquidity = tokenIsZero
            ? FullMath.mulDiv(budget, FullMath.mulDiv(sqrtA, sqrtB, Q96), sqrtB - sqrtA)
            : FullMath.mulDiv(budget, Q96, sqrtB - sqrtA);
        _modify(int256(seededLiquidity));
    }

    function _modify(int256 liquidityDelta) internal returns (BalanceDelta) {
        bytes memory result = manager.unlock(
            abi.encode(uint8(1), abi.encode(ModifyLiquidityParams(lowerTick, upperTick, liquidityDelta, bytes32(0))))
        );
        return abi.decode(result, (BalanceDelta));
    }

    function _donate(uint256 scAmount, uint256 pairAmount) internal returns (BalanceDelta) {
        (uint256 a0, uint256 a1) = tokenIsZero ? (scAmount, pairAmount) : (pairAmount, scAmount);
        return abi.decode(manager.unlock(abi.encode(uint8(2), abi.encode(a0, a1))), (BalanceDelta));
    }

    /// @dev Positive `amount` is exact output, negative is exact input, as in v4.
    function _swap(bool zeroForOne, int256 amount) internal returns (BalanceDelta) {
        uint160 limit = zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;
        return abi.decode(
            manager.unlock(abi.encode(uint8(0), abi.encode(SwapParams(zeroForOne, amount, limit)))), (BalanceDelta)
        );
    }

    function _scDelta(BalanceDelta delta) internal view returns (int256) {
        return tokenIsZero ? int256(delta.amount0()) : int256(delta.amount1());
    }

    function _pairDelta(BalanceDelta delta) internal view returns (int256) {
        return tokenIsZero ? int256(delta.amount1()) : int256(delta.amount0());
    }

    function unlockCallback(bytes calldata data) external virtual returns (bytes memory) {
        require(msg.sender == MANAGER, "only manager");
        (uint8 action, bytes memory parameters) = abi.decode(data, (uint8, bytes));
        BalanceDelta delta;
        if (action == 0) {
            delta = manager.swap(key, abi.decode(parameters, (SwapParams)), "");
        } else if (action == 1) {
            (delta,) = manager.modifyLiquidity(key, abi.decode(parameters, (ModifyLiquidityParams)), "");
        } else {
            (uint256 a0, uint256 a1) = abi.decode(parameters, (uint256, uint256));
            delta = manager.donate(key, a0, a1, "");
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

/// @notice Swaps through the real PoolManager with both the LP fee and the protocol fee charged.
contract V4ProtocolFeesTest is V4FeeFixture {
    function setUp() public {
        _deployFixture();
        pair.mint(address(this), 1_000 ether);
    }

    function test_FixtureIsAtTheRequestedEconomics() public view {
        assertEq(manager.protocolFeeController(), address(this));
        assertEq(key.fee, 12500);
        assertEq(key.tickSpacing, 60);
        assertEq(pair.balanceOf(MANAGER), 0, "seed must be single sided");
        assertEq(token.balanceOf(address(this)) + token.balanceOf(MANAGER), SUPPLY * 9 / 10);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ExactInputBuyWithProtocolFeePaysTaxOnlyOnTheOutput() public {
        uint256 remainder = token.balanceOf(address(this));
        uint256 pairBefore = pair.balanceOf(address(this));
        BalanceDelta delta = _swap(!tokenIsZero, -int256(0.01 ether));
        uint256 gross = uint256(_scDelta(delta));
        assertGt(gross, 0);
        assertEq(uint256(-_pairDelta(delta)), 0.01 ether, "exact input must be consumed in full");
        assertEq(pair.balanceOf(address(this)), pairBefore - 0.01 ether);
        assertGt(manager.protocolFeesAccrued(Currency.wrap(PAIRED)), 0, "protocol fee accrues on the input");
        assertEq(manager.protocolFeesAccrued(Currency.wrap(address(token))), 0);
        uint256 tax = gross / 50;
        assertEq(token.balanceOf(address(this)) - remainder, gross - tax, "buyer receives net");
        assertEq(token.balanceOf(CREATOR), tax);
        assertEq(token.balanceOf(MANAGER), seeded - gross, "manager loses gross");
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ExactOutputBuyDeliversNinetyEightPercentOfTheRequestedAmount() public {
        uint256 remainder = token.balanceOf(address(this));
        uint256 want = 1_000 ether;
        BalanceDelta delta = _swap(!tokenIsZero, int256(want));
        assertEq(uint256(_scDelta(delta)), want, "pool quotes the exact output");
        assertLt(_pairDelta(delta), 0);
        assertEq(token.balanceOf(address(this)) - remainder, want - want / 50);
        assertEq(token.balanceOf(CREATOR), want / 50);
        assertEq(token.balanceOf(MANAGER), seeded - want);
    }

    function test_DustExactOutputBuyPaysNoTax() public {
        uint256 remainder = token.balanceOf(address(this));
        BalanceDelta delta = _swap(!tokenIsZero, int256(49));
        assertEq(uint256(_scDelta(delta)), 49);
        assertEq(token.balanceOf(address(this)) - remainder, 49);
        assertEq(token.balanceOf(CREATOR), 0);
        _swap(!tokenIsZero, int256(50));
        assertEq(token.balanceOf(address(this)) - remainder, 49 + 49);
        assertEq(token.balanceOf(CREATOR), 1);
    }

    function test_SellWithProtocolFeeSettlesExactlyAndAccruesScFees() public {
        uint256 remainder = token.balanceOf(address(this));
        BalanceDelta buy = _swap(!tokenIsZero, -int256(0.5 ether));
        uint256 gross = uint256(_scDelta(buy));
        uint256 bought = token.balanceOf(address(this)) - remainder;
        uint256 pairBefore = pair.balanceOf(address(this));

        BalanceDelta sell = _swap(tokenIsZero, -int256(bought));
        assertEq(uint256(-_scDelta(sell)), bought, "the whole net purchase is accepted as input");
        assertGt(pair.balanceOf(address(this)), pairBefore);
        assertEq(token.balanceOf(address(this)), remainder, "nothing bought is stuck");
        assertEq(token.balanceOf(MANAGER), seeded - gross + bought, "sell arrives whole");
        assertEq(token.balanceOf(CREATOR), gross / 50, "no tax on the sell");
        uint256 accrued = manager.protocolFeesAccrued(Currency.wrap(address(token)));
        assertGt(accrued, 0, "protocol fee accrues on SC when SC is the input");
        assertLe(accrued, token.balanceOf(MANAGER));
    }

    /// @dev Spec M1 taxes every transfer from the PoolManager, so the protocol's own fee collection
    /// in SC is a taxed outflow: the fee recipient gets 98%, the creator 2%. Collection in IMD is whole.
    function test_ProtocolFeeCollectionInScIsATaxedOutflow() public {
        uint256 remainder = token.balanceOf(address(this));
        _swap(!tokenIsZero, -int256(0.5 ether));
        uint256 bought = token.balanceOf(address(this)) - remainder;
        _swap(tokenIsZero, -int256(bought));
        uint256 creatorBefore = token.balanceOf(CREATOR);
        uint256 managerBefore = token.balanceOf(MANAGER);
        uint256 accrued = manager.protocolFeesAccrued(Currency.wrap(address(token)));
        assertGe(accrued, 50, "fixture must accrue a taxable amount");

        address treasury = makeAddr("protocol treasury");
        uint256 collected = manager.collectProtocolFees(treasury, Currency.wrap(address(token)), 0);
        assertEq(collected, accrued);
        assertEq(manager.protocolFeesAccrued(Currency.wrap(address(token))), 0);
        assertEq(token.balanceOf(MANAGER), managerBefore - accrued, "manager debits the gross");
        assertEq(token.balanceOf(treasury), accrued - accrued / 50, "treasury receives net of tax");
        assertEq(token.balanceOf(CREATOR), creatorBefore + accrued / 50);

        uint256 pairAccrued = manager.protocolFeesAccrued(Currency.wrap(PAIRED));
        assertGt(pairAccrued, 0);
        manager.collectProtocolFees(treasury, Currency.wrap(PAIRED), 0);
        assertEq(pair.balanceOf(treasury), pairAccrued, "IMD collection is untouched");
    }

    function test_StrangerCannotCollectProtocolFeesOrChangeThem() public {
        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        vm.expectRevert();
        manager.collectProtocolFees(stranger, Currency.wrap(address(token)), 0);
        vm.prank(stranger);
        vm.expectRevert();
        manager.setProtocolFee(key, 0);
        assertEq(token.balanceOf(stranger), 0);
    }

    /// @dev Removing liquidity is also a transfer from the PoolManager: the provider receives 98% of
    /// its SC and all of its IMD. Donating into the pool is an inflow and is never taxed.
    function test_LiquidityRemovalIsTaxedAndDonationIsNot() public {
        _swap(!tokenIsZero, -int256(1 ether)); // move the price into the seeded range
        uint256 remainder = token.balanceOf(address(this));
        uint256 creatorBefore = token.balanceOf(CREATOR);
        uint256 managerBefore = token.balanceOf(MANAGER);

        BalanceDelta donated = _donate(1_000 ether, 0.001 ether);
        assertEq(_scDelta(donated), -int256(1_000 ether));
        assertEq(token.balanceOf(MANAGER), managerBefore + 1_000 ether, "donation arrives whole");
        assertEq(token.balanceOf(CREATOR), creatorBefore, "donation is not taxed");
        assertEq(token.balanceOf(address(this)), remainder - 1_000 ether);
        remainder = token.balanceOf(address(this));
        managerBefore = token.balanceOf(MANAGER);

        BalanceDelta removed = _modify(-int256(seededLiquidity / 4));
        uint256 scOut = uint256(_scDelta(removed));
        uint256 pairOut = uint256(_pairDelta(removed));
        assertGt(scOut, 0);
        assertGt(pairOut, 0, "pool holds IMD from the buy and donation");
        assertEq(token.balanceOf(address(this)) - remainder, scOut - scOut / 50, "provider receives net");
        assertEq(token.balanceOf(CREATOR), creatorBefore + scOut / 50);
        assertEq(token.balanceOf(MANAGER), managerBefore - scOut);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_BuyerCanAlwaysSellBackEverythingReceived() public {
        uint256 remainder = token.balanceOf(address(this));
        uint256 totalTax;
        uint256 scInManager = seeded;
        for (uint256 i = 1; i <= 5; ++i) {
            BalanceDelta buy = _swap(!tokenIsZero, -int256(i * 0.1 ether));
            uint256 gross = uint256(_scDelta(buy));
            totalTax += gross / 50;
            uint256 bought = token.balanceOf(address(this)) - remainder;
            assertEq(bought, gross - gross / 50);
            BalanceDelta sell = _swap(tokenIsZero, -int256(bought));
            assertEq(uint256(-_scDelta(sell)), bought);
            assertEq(token.balanceOf(address(this)), remainder);
            scInManager = scInManager - gross + bought;
            assertEq(token.balanceOf(MANAGER), scInManager);
        }
        assertEq(token.balanceOf(CREATOR), totalTax);
        assertEq(token.totalSupply(), SUPPLY);
    }
}

/// @notice An ordinary trader driven by the invariant fuzzer: buys with fresh IMD, sells what it
/// holds, both through the real PoolManager with fees on, and records what the pool reported.
contract V4TraderHandler is Test, IUnlockCallback {
    address internal constant MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    IPoolManager internal immutable manager = IPoolManager(MANAGER);
    SCToken public immutable token;
    PairFixture public immutable pair;
    PoolKey internal key;
    bool internal immutable tokenIsZero;

    uint256 public grossOut;
    uint256 public soldIn;
    uint256 public cumulativeTax;
    uint256 public buys;
    uint256 public sells;

    constructor(SCToken token_, PairFixture pair_, PoolKey memory key_, bool tokenIsZero_) {
        token = token_;
        pair = pair_;
        key = key_;
        tokenIsZero = tokenIsZero_;
    }

    function buy(uint256 pairIn) external {
        pairIn = bound(pairIn, 1, 1 ether);
        pair.mint(address(this), pairIn);
        uint256 before = token.balanceOf(address(this));
        BalanceDelta delta = _swap(!tokenIsZero, -int256(pairIn));
        int256 sc = tokenIsZero ? int256(delta.amount0()) : int256(delta.amount1());
        assertGe(sc, 0, "a buy never debits SC");
        uint256 gross = uint256(sc);
        grossOut += gross;
        cumulativeTax += gross / 50;
        assertEq(token.balanceOf(address(this)) - before, gross - gross / 50, "buyer must receive net");
        ++buys;
    }

    function sell(uint256 scIn) external {
        uint256 held = token.balanceOf(address(this));
        if (held == 0) return;
        scIn = bound(scIn, 1, held);
        BalanceDelta delta = _swap(tokenIsZero, -int256(scIn));
        int256 sc = tokenIsZero ? int256(delta.amount0()) : int256(delta.amount1());
        assertLe(sc, 0, "a sell never credits SC");
        uint256 paid = uint256(-sc);
        assertLe(paid, scIn);
        soldIn += paid;
        assertEq(token.balanceOf(address(this)), held - paid, "sell debits exactly what was settled");
        ++sells;
    }

    function _swap(bool zeroForOne, int256 amount) internal returns (BalanceDelta) {
        uint160 limit = zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;
        return abi.decode(manager.unlock(abi.encode(SwapParams(zeroForOne, amount, limit))), (BalanceDelta));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == MANAGER, "only manager");
        BalanceDelta delta = manager.swap(key, abi.decode(data, (SwapParams)), "");
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
}

/// @notice Random buy/sell sequences through the real PoolManager with the LP and protocol fees on.
contract V4SwapInvariantTest is StdInvariant, V4FeeFixture {
    V4TraderHandler internal handler;
    address internal distributor;

    function setUp() public {
        _deployFixture();
        distributor = makeAddr("distributor");
        handler = new V4TraderHandler(token, pair, key, tokenIsZero);
        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = V4TraderHandler.buy.selector;
        selectors[1] = V4TraderHandler.sell.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// forge-config: default.invariant.runs = 64
    /// forge-config: default.invariant.depth = 32
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_PoolAccountingMatchesTokenBalances() public view {
        uint256 managerHeld = token.balanceOf(MANAGER);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(
            managerHeld + token.balanceOf(address(handler)) + token.balanceOf(CREATOR) + token.balanceOf(address(this))
                + token.balanceOf(distributor),
            SUPPLY,
            "SC is not conserved"
        );
        assertEq(token.balanceOf(CREATOR), handler.cumulativeTax(), "creator holds exactly 2% of every buy");
        assertEq(managerHeld, seeded - handler.grossOut() + handler.soldIn(), "manager balance drifted");
        assertEq(
            token.balanceOf(address(handler)),
            handler.grossOut() - handler.cumulativeTax() - handler.soldIn(),
            "trader balance drifted"
        );
        assertLe(
            manager.protocolFeesAccrued(Currency.wrap(address(token))),
            managerHeld,
            "manager must hold at least its accrued SC protocol fees"
        );
        assertEq(token.balanceOf(distributor), SUPPLY / 10, "the swarm share is untouched by trading");
    }
}
