# Vendored dependencies

These are ordinary source files, not submodules. Only the required source and
license files were extracted; upstream configuration, workflows, environments,
tests, build artifacts and package-install machinery were not imported.

| Directory | Pinned source | Purpose | License |
| --- | --- | --- | --- |
| `lib/openzeppelin-contracts` | [OpenZeppelin Contracts v5.0.2](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.0.2) | ERC-20, its interfaces and Context | MIT; `lib/openzeppelin-contracts/LICENSE` |
| `lib/forge-std` | [forge-std v1.9.7](https://github.com/foundry-rs/forge-std/tree/v1.9.7) | Foundry tests only | MIT / Apache-2.0; both license files are included |
| `lib/v4-core` | [@uniswap/v4-core 1.0.2](https://www.npmjs.com/package/@uniswap/v4-core/v/1.0.2) | Offline PoolManager integration tests only | Per-file BUSL-1.1 or MIT; `lib/v4-core/licenses/` |
| `lib/solmate` | Files bundled in `@uniswap/v4-core` 1.0.2 | Dependencies of the offline v4 fixture only | AGPL-3.0 license plus per-file identifiers; `lib/solmate/LICENSE` |

Original archive SHA-256 hashes:

```text
forge-std v1.9.7 GitHub tag archive:
45157353ab49eab01d294565866731e599b32401757229689ee459aa26b7ee94
OpenZeppelin Contracts v5.0.2 GitHub tag archive:
18c7b7e949b9a82dcd8cd394426c9c2636dfc263aa2317d4749dbfa0c7b3925a
@uniswap/v4-core 1.0.2 npm archive:
f3db3af55f3d0c52f16abe96e7db12443f243bca1f334962373f95c57611de49
```

Only OpenZeppelin's ERC-20 subset is imported by the launch contract. The
PoolManager, test pair token, test handlers and test ownership utilities are not
launch contracts and are not entries in `launch.json`.
