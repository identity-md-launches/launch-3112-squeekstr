# Vendored dependencies

Dependencies are copied as ordinary source files, preserving their upstream contents and licenses.
There are no submodules, package-manager hooks, generated compiler binaries, or build-time downloads.

| Dependency | Release and immutable revision | Included subset | License |
| --- | --- | --- | --- |
| [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/69c8def5f222ff96f2b5beff05dfba996368aa79) | v5.1.0, `69c8def5f222ff96f2b5beff05dfba996368aa79` | `ERC20`, `IERC20`, `IERC20Metadata`, `Context`, `draft-IERC6093`, and license | [MIT](lib/openzeppelin-contracts/LICENSE) |
| [forge-std](https://github.com/foundry-rs/forge-std/tree/77041d2ce690e692d6e03cc812b57d1ddaa4d505) | v1.9.7, `77041d2ce690e692d6e03cc812b57d1ddaa4d505` | Solidity `src/` and licenses; used only by tests | [MIT](lib/forge-std/LICENSE-MIT) or [Apache-2.0](lib/forge-std/LICENSE-APACHE) |

The imports are resolved by explicit remappings in `foundry.toml`. Only the OpenZeppelin subset is
in the production token's import graph. forge-std is test support and is not deployed.

[lib/dependencies.json](lib/dependencies.json) records each upstream repository, version, commit,
downloaded archive SHA-256, and installed file count. [lib/SHA256SUMS](lib/SHA256SUMS) records every
vendored source/license file hash. Verify the installed copies from the repository root with:

```sh
sha256sum --check lib/SHA256SUMS
```

No content from the supplied security reference is redistributed in the production source.
