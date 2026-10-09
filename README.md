# SwarmCity (SC)

`src/SCToken.sol` is the sole launch contract. Its zero-argument constructor mints
1,000,000,000 SC (1e27 minor units, 18 decimals) to its deployer. It has no owner,
admin, external mint/burn functions, upgrade mechanism or external calls.

Every transfer from Ethereum's Uniswap v4 PoolManager
`0x000000000004444c5dc75cB358380D2e3dE08A90` deducts 2% for
`0xD30eA9E0FA0C671BB4dC6C6e83863396B1822951`. The fee rounds down to the nearest
minor unit; transfers smaller than 50 minor units consequently pay zero. The
manager loses the gross amount and the recipient receives the net amount.
`transferFrom` spends allowance for the gross amount. All transfers **to** the
manager, including manager self-transfers, and ordinary wallet transfers are
tax-free. The rate, recipient and manager are compile-time constants.

The launch factory performs the swarm distribution and pool seeding after
deployment. The token does not distribute any supply in its constructor beyond
minting the entire amount to the deployer. `launch.json` records the requested
90% pool allocation, IMD pair, 1.25% pool fee, tick spacing 60 and 2,500 IMD
opening market cap. Its supplied initial price is provenance; the factory derives
the opening price using the economics and deployed currency order.

Build and test with the installed Foundry toolchain:

```sh
forge build --offline
forge test --offline
```

Solidity 0.8.26, Cancun, optimizer (200 runs), and `bytecode_hash = "none"` are
pinned in `foundry.toml`. Every Solidity dependency is vendored as ordinary
files under `lib/`; no install step, submodule, network, RPC or key is needed.
[THIRD_PARTY.md](THIRD_PARTY.md) records versions and licenses.

The 23 tests cover launch distribution, gross/net tax accounting and events,
rounding, zero and self-transfers, the creator receiving or spending tokens,
allowances, reverting transfers, absent privileged entry points, and forbidden
runtime opcodes. Three fuzz tests each run 1,000 cases. The stateful invariant
runs 256 sequences of 64 transfers, checking fixed supply, conservation and
cumulative creator tax. The integration suite runs the actual vendored Uniswap
v4 PoolManager locally at its canonical address, with an ordinary ERC-20 IMD
fixture. It exercises single-sided seeding and a buy/sell round trip in both
currency orders at the requested fee, spacing and opening economics. This is
offline integration coverage; no live-mainnet fork or broadcast was performed.
The separate network-supplied protected harness is not part of the local suite.

## Deployment parameters

| Parameter | Value |
| --- | --- |
| Chain | Ethereum mainnet (chain id 1) |
| Contract | `SCToken` (`src/SCToken.sol`), zero constructor arguments |
| Name / symbol / decimals | SwarmCity / SC / 18 |
| Total supply | 1,000,000,000 SC = 1e27 minor units, minted once to the deployer |
| Uniswap v4 PoolManager | `0x000000000004444c5dc75cB358380D2e3dE08A90` (constant) |
| Tax | 200 bps on transfers from the PoolManager, rounded down |
| Tax recipient | `0xD30eA9E0FA0C671BB4dC6C6e83863396B1822951` (constant) |
| Paired currency | IMD `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7` |
| Pool fee / tick spacing | 12500 (1.25%) / 60 |
| Pool share / opening cap | 9000 bps / 2,500 IMD (`economics` in `launch.json`) |
| Remainder recipient | `0x000000000000000000000000000000000000dead` |

Nothing is configurable after deployment. There is no owner, no setter and no
"after launch" step for the token itself.

## Assumptions and operational responsibilities

- The deployer is the launch factory. Whoever deploys receives the whole
  supply; the token never reserves, burns or forwards any part of it.
- The swarm's 10%, the 90% pool seed and the remainder are the factory's
  flows. The token taxes none of them: the seed moves tokens **to** the
  PoolManager, and the distributor and claimants are ordinary wallets.
- The PoolManager address is Ethereum mainnet's. Deploying the same bytecode on
  another chain gives a token with a working ERC-20 but no tax, because no
  transfer would originate from that address there.
- Every outflow from the PoolManager is taxed, whichever contract or router
  calls `take`. A buyer therefore receives 98% of the swap's quoted output.
  Sells and liquidity removals that send tokens into the PoolManager settle
  exactly, so v4 accounting always balances.
- The tax recipient wallet is a compile-time constant. The requester is
  responsible for controlling that wallet's key; the contract cannot redirect
  or recover tax sent to it.
- Amounts below 50 minor units leaving the PoolManager pay no tax because the
  fee rounds down. This is dust and cannot be farmed meaningfully given gas.
- Nobody deploys, broadcasts or holds keys from this repository. Explorer
  verification uses the pinned compiler settings in `foundry.toml`.
- Tests passing is not an audit. A separate adversarial review before release
  is the launch policy's responsibility. No live-mainnet fork test was run.

## Logos

The five logo options are listed in [logos/README.md](logos/README.md). Each is
an opaque 1024x1024 PNG drawn by the built-in OpenAI image generation tool from
the creator's reference. **Five drafts were drawn, one per requested approach;
all five were retained, and none was rejected.** Option 2 (`logos/logo-2.png`)
is the recommended mark: its single geometric shape reads most clearly in a
32-pixel circle. All options were inspected at 64 pixels on both light and dark
surfaces. The artwork was generated as a bitmap; export processing only resized
it. [logos/GENERATION.md](logos/GENERATION.md) records the prompt set and
selection.
