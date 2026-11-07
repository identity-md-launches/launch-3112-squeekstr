# SQUEEKSTR (SQKSTR)

Fixed-supply ERC-20 for the project identified in the brief as **sqkstr.xyz**.

| Property | Value |
| --- | --- |
| Contract | `src/SQUEEKSTR.sol:SQUEEKSTR` |
| Token name | `SQUEEKSTR` |
| Symbol | `SQKSTR` |
| Decimals | `18` |
| Whole-token supply | `1,000,000,000` |
| Supply in base units | `1000000000000000000000000000` (`10^27`) |
| Initial holder | Immediate deployer (`msg.sender` in the constructor) |
| Constructor arguments | None (`[]`) |
| Deployment ETH value | `0` |
| Intended launch chain | Ethereum, chain ID `1` |

The constructor mints the entire supply once and emits the standard mint `Transfer` event.
`INITIAL_SUPPLY` is the named constant for that issuance. The token uses the vendored
OpenZeppelin Contracts v5.1.0 ERC-20 implementation without overriding its transfer behavior.

## Behavior and assumptions

The requested on-chain behavior is a standard transferable token with fixed issuance. The supplied
website reference does not introduce an oracle, external service, redemption promise, or additional
application contract.

- Transfers move exactly the requested amount. There are no token taxes, transfer burns, rebases,
  trading gates, wallet limits, or address exemptions.
- `approve` sets the caller's allowance for a spender. `transferFrom` checks and consumes that
  allowance. The maximum `uint256` allowance represents unlimited approval and does not decrease.
- Successful transfers and approvals return `true`. Invalid operations revert with OpenZeppelin's
  ERC-6093 custom errors. Failures revert the entire operation, including any allowance update.
- Zero-value transfers to nonzero addresses are supported and emit `Transfer`. Self-transfers
  preserve the balance while still requiring sufficient funds. Zero-address recipients and
  zero-address approval spenders are rejected.
- `approve` emits `Approval`; `transferFrom` emits `Transfer` but does not emit an additional
  `Approval` event when spending allowance. Integrations should read `allowance()` for current state.
- There is no owner, mint endpoint, burn endpoint, pause, blacklist, seizure, rescue, initializer,
  proxy, upgrade mechanism, or permit extension. No account can alter the issuance or transfer rules.
- The token makes no external calls. Its constructor needs no external contracts, settings, or
  keys. Calls sending ETH revert; forcibly received ETH and assets sent to the token contract
  cannot be recovered through this contract.

## Build and check

Run from the repository root with Foundry and Solidity **0.8.26** installed:

```sh
forge build
FOUNDRY_FUZZ_SEED=0x92693da3eff2bad75863123432f1ba00fd4c132a512088727736d5c105ecdbe5 forge test -vv
forge fmt --check
```

`foundry.toml` pins Solidity 0.8.26, Cancun EVM, optimization with 200 runs, and
`bytecode_hash = "none"`. FFI and filesystem cheatcode permissions are not enabled. All Solidity
dependencies are ordinary files under `lib/`; no dependency installation, git submodule, RPC,
environment secrets, or network connection is needed to build or test with the compiler installed.
Dependency commits, licenses, and checksums are documented in [DEPENDENCIES.md](DEPENDENCIES.md).

The test suite contains:

- Constructor issuance, metadata, mint event, and CREATE2 deployment through a factory, checking
  that the factory receives the supply even when the transaction origin and caller differ.
- Exact launch-role transfers and a distributor claim, followed by token transfers from a pool
  role to a trader and back. This is a token accounting test, not an actual Uniswap swap simulation.
- Transfers, full-balance and zero-value transfers, self-transfers, approval replacement/revocation,
  finite and unlimited allowances, and transfer/approval events.
- Rejection of insufficient balance or allowance, unapproved spenders, zero addresses, absent
  administrative/mint/burn/upgrade selectors, unknown calls, and direct ETH payments; failed
  `transferFrom` operations must restore the allowance.
- Four fuzz tests with 1,024 cases each, including valid transfers and adversarial amounts/callers.
- Stateful invariants over 128 sequences of 64 actions, comparing balances and allowances against
  an independent accounting model and checking constant supply and conservation of balances.

The tests create their own local state and use no environment-reading or environment-setting
cheatcodes. The supplied seed is passed to the test command, not pinned over verifier settings.

## Deployment parameters and responsibilities

The deployable artifact is `out/SQUEEKSTR.sol/SQUEEKSTR.json`. Its constructor has no arguments,
requires no initialization call, and has no linked library addresses. The creation bytecode can be
inspected locally without broadcasting:

```sh
forge inspect src/SQUEEKSTR.sol:SQUEEKSTR bytecode
forge inspect src/SQUEEKSTR.sol:SQUEEKSTR abi
```

The launch operator deploys that bytecode with zero ETH. **The address actually executing CREATE or
CREATE2 receives every token.** In the specified IdentityMD launch this is the launch factory. A
deployment helper or another factory would receive the issuance instead of its caller, so the
operator must use the intended deployment path and a factory capable of distributing the balance.

The launch factory is responsible for distributing its supply and providing liquidity. The supplied
launch terms allocate 10% (100,000,000 SQKSTR) to the launch distributor, 60% (600,000,000 SQKSTR) to
the pool, and 30% (300,000,000 SQKSTR) to `0xee2aaa315cf7ed169f93148d30d24af9318dbb66`.
These are factory operations after construction; the token itself makes no allocations.
The supplied pool terms are the IMD pair at `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7`, fee `12500`
(1.25%), tick spacing `60`, and initial whole-supply market cap `3000000000000000000000` in the
pair's base units (3,000 IMD). The launch system derives the opening pool price. These terms are not
token constructor parameters or a token transfer fee. The separate launch process creates the
manifest; this repository supplies the token artifact and no application contracts.

Before release the operator is responsible for independent review, the network's full factory and
Uniswap integration checks, confirming chain/bytecode/metadata/supply and initial custody, and
publishing the deployed address and verified source. The supplied protected integration tests
depend on launch infrastructure and manifest inputs outside this standalone project; they are run
by the launch verifier. No deployment or transaction broadcast is part of this deliverable.

## After launch

There are **no owner settings, required setters, privileged operators, or maintenance transactions**.
The initial holder distributes the supply through normal ERC-20 transfers. Holders control their
balances and allowances; approved spenders can transfer up to their allowance. Holders should use
bounded approvals where possible and revoke unused approvals. To replace a nonzero approval,
revoke it and wait for confirmation before granting the replacement; revocation cannot undo
tokens already spent. The issuer cannot reverse mistakes, recover lost assets, freeze holders, or
upgrade the token.

See [SECURITY.md](SECURITY.md) for the local review scope and remaining release responsibilities.
