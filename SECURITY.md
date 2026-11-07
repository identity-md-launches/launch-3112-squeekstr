# Security review scope

The production contract consists of a constructor-only supply policy over the vendored
OpenZeppelin ERC-20 implementation. Its public state-changing surface is `transfer`, `approve`,
and `transferFrom`. The deployer has an initial balance but no privileged role.

The supplied `eth-security` reference informed the local source review. Findings applicable to
this implementation were checked against the actual code:

| Area | Review result |
| --- | --- |
| Issuance and decimal arithmetic | The sole `_mint` call is in the constructor, for `1_000_000_000 * 10**18`. There is no callable mint or burn route after construction. |
| Authorization | Transfers debit the caller, or a holder who granted the caller sufficient allowance. The deployer has no bypass. |
| Arithmetic and rollback | The vendored implementation validates balances/allowances before subtraction. Failed transactions roll back allowance changes. Self-transfers are supported. |
| External interaction and reentrancy | No external calls, hooks, recipient callbacks, oracle dependencies, or native-currency payouts occur. No reentrancy guard is needed for this call surface. |
| Integration behavior | Transfers have no fee or hidden balance change. Approvals follow standard ERC-20 behavior, including maximum allowance semantics. |
| Administrative powers | No ownership, pause, seizure, blacklist, rescue, upgrade path, or initialization path. |
| Dangerous execution paths | No proxy, delegatecall, callcode, selfdestruct, signature verification, or dynamic library linking is used by production code. |
| Deployment custody | The immediate CREATE/CREATE2 caller receives the supply. Factory deployment is explicitly tested. |

Local validation uses `forge build`, `forge test`, and `forge fmt --check` with Solidity 0.8.26.
The suite includes boundary/error tests, four seeded fuzz tests, and stateful conservation and
allowance-model invariants. Dependency file hashes are checked against the vendored records.
Slither and Mythril were not run. No mainnet fork, real pool swap, transaction broadcast, or explorer
verification was performed. The local role-flow test does not replace the supplied launch verifier's
real PoolManager tests.

This review and passing tests are not an independent security audit. Independent adversarial review
and the launch verifier's checks remain release responsibilities. The operator must confirm the
deployed bytecode and metadata and publish source verification after deployment.

Operational limitations are deliberate: holders bear custody and approval responsibility; there is
no recovery mechanism or emergency administrator. Standard ERC-20 approval replacement ordering
risks and unlimited approvals remain relevant. Assets sent directly to the token contract cannot be
rescued. The token cannot be patched after deployment.
