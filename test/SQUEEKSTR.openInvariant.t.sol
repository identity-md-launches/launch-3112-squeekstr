// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SQUEEKSTR} from "../src/SQUEEKSTR.sol";

/// @dev Unlike the closed four-holder handler, recipients here are arbitrary fuzzed addresses
///      (including the token contract itself), every holder ever touched is tracked, and every
///      failure path is attempted with try/catch so that the handler can check that a reverted
///      call changed nothing at all.
contract OpenTokenHandler is Test {
    SQUEEKSTR public immutable token;
    address[] public holders;
    mapping(address => bool) public known;
    mapping(address => uint256) public ghostBalance;
    mapping(address => mapping(address => uint256)) public ghostAllowance;

    uint256 public ghostTransferred;
    uint256 public successes;
    uint256 public expectedFailures;
    uint256 public unexpectedOutcomes;

    constructor(SQUEEKSTR token_, address seedHolder, uint256 supply) {
        token = token_;
        _track(seedHolder);
        ghostBalance[seedHolder] = supply;
    }

    function holderCount() external view returns (uint256) {
        return holders.length;
    }

    // ------------------------------------------------------------ successful paths

    function transferToAnyone(uint256 fromSeed, address to, uint256 rawAmount) external {
        if (to == address(0)) to = address(token);
        address from = _holder(fromSeed);
        uint256 amount = bound(rawAmount, 0, ghostBalance[from]);
        _track(to);
        vm.prank(from);
        bool ok = token.transfer(to, amount);
        if (!ok) unexpectedOutcomes++;
        ghostBalance[from] -= amount;
        ghostBalance[to] += amount;
        ghostTransferred += amount;
        successes++;
    }

    function approveAnyone(uint256 ownerSeed, address spender, uint256 amount) external {
        if (spender == address(0)) return;
        address owner = _holder(ownerSeed);
        _track(spender);
        vm.prank(owner);
        bool ok = token.approve(spender, amount);
        if (!ok) unexpectedOutcomes++;
        ghostAllowance[owner][spender] = amount;
        successes++;
    }

    function spendAllowance(uint256 ownerSeed, uint256 spenderSeed, address to, uint256 rawAmount) external {
        if (to == address(0)) to = address(token);
        address owner = _holder(ownerSeed);
        address spender = _holder(spenderSeed);
        uint256 approved = ghostAllowance[owner][spender];
        uint256 bal = ghostBalance[owner];
        uint256 amount = bound(rawAmount, 0, approved < bal ? approved : bal);
        _track(to);
        vm.prank(spender);
        bool ok = token.transferFrom(owner, to, amount);
        if (!ok) unexpectedOutcomes++;
        ghostBalance[owner] -= amount;
        ghostBalance[to] += amount;
        if (approved != type(uint256).max) ghostAllowance[owner][spender] = approved - amount;
        ghostTransferred += amount;
        successes++;
    }

    // ------------------------------------------------------------ failure paths

    function failOverdraft(uint256 fromSeed, uint256 toSeed, uint256 rawExcess) external {
        address from = _holder(fromSeed);
        address to = _holder(toSeed);
        uint256 bal = ghostBalance[from];
        uint256 amount = bal + bound(rawExcess, 1, type(uint256).max - bal);
        bytes memory expected =
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, bal, amount);
        vm.prank(from);
        try token.transfer(to, amount) {
            unexpectedOutcomes++;
        } catch (bytes memory reason) {
            _expectReason(reason, expected);
        }
    }

    function failToZero(uint256 fromSeed, uint256 rawAmount) external {
        address from = _holder(fromSeed);
        uint256 amount = bound(rawAmount, 0, ghostBalance[from]);
        bytes memory expected = abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0));
        vm.prank(from);
        try token.transfer(address(0), amount) {
            unexpectedOutcomes++;
        } catch (bytes memory reason) {
            _expectReason(reason, expected);
        }
    }

    function failOverAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) external {
        address owner = _holder(ownerSeed);
        address spender = _holder(spenderSeed);
        address to = _holder(toSeed);
        uint256 approved = ghostAllowance[owner][spender];
        if (approved == type(uint256).max) return;
        uint256 amount = approved + 1;
        // The allowance is checked before the balance, so this error wins whatever the balance.
        bytes memory expected = abi.encodeWithSelector(
            IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount
        );
        vm.prank(spender);
        try token.transferFrom(owner, to, amount) {
            unexpectedOutcomes++;
        } catch (bytes memory reason) {
            _expectReason(reason, expected);
        }
    }

    function failAllowanceAboveBalance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) external {
        address owner = _holder(ownerSeed);
        address spender = _holder(spenderSeed);
        address to = _holder(toSeed);
        uint256 approved = ghostAllowance[owner][spender];
        uint256 bal = ghostBalance[owner];
        if (approved <= bal) return;
        uint256 amount = bal + 1;
        bytes memory expected =
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, bal, amount);
        vm.prank(spender);
        try token.transferFrom(owner, to, amount) {
            unexpectedOutcomes++;
        } catch (bytes memory reason) {
            _expectReason(reason, expected);
        }
    }

    function failApproveZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = _holder(ownerSeed);
        bytes memory expected = abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0));
        vm.prank(owner);
        try token.approve(address(0), amount) {
            unexpectedOutcomes++;
        } catch (bytes memory reason) {
            _expectReason(reason, expected);
        }
    }

    // ------------------------------------------------------------ helpers

    function _expectReason(bytes memory reason, bytes memory expected) private {
        if (keccak256(reason) != keccak256(expected)) unexpectedOutcomes++;
        else expectedFailures++;
    }

    function _holder(uint256 seed) private view returns (address) {
        return holders[seed % holders.length];
    }

    function _track(address a) private {
        if (!known[a]) {
            known[a] = true;
            holders.push(a);
        }
    }
}

contract SQUEEKSTROpenInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    SQUEEKSTR internal token;
    OpenTokenHandler internal handler;
    address internal seedHolder;

    function setUp() public {
        token = new SQUEEKSTR();
        seedHolder = makeAddr("open invariant seed holder");
        handler = new OpenTokenHandler(token, seedHolder, SUPPLY);
        token.transfer(seedHolder, SUPPLY);

        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = OpenTokenHandler.transferToAnyone.selector;
        selectors[1] = OpenTokenHandler.approveAnyone.selector;
        selectors[2] = OpenTokenHandler.spendAllowance.selector;
        selectors[3] = OpenTokenHandler.failOverdraft.selector;
        selectors[4] = OpenTokenHandler.failToZero.selector;
        selectors[5] = OpenTokenHandler.failOverAllowance.selector;
        selectors[6] = OpenTokenHandler.failAllowanceAboveBalance.selector;
        selectors[7] = OpenTokenHandler.failApproveZeroSpender.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_SupplyIsFixedAndFullyAccounted() public view {
        assertEq(token.totalSupply(), SUPPLY);
        uint256 n = handler.holderCount();
        uint256 sum;
        for (uint256 i; i < n; ++i) {
            sum += token.balanceOf(handler.holders(i));
        }
        assertEq(sum, SUPPLY, "tracked holders do not hold the whole supply");
        assertEq(token.balanceOf(address(0)), 0);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_StateMatchesGhostModel() public view {
        uint256 n = handler.holderCount();
        for (uint256 i; i < n; ++i) {
            address owner = handler.holders(i);
            assertEq(token.balanceOf(owner), handler.ghostBalance(owner), "balance diverged from model");
            for (uint256 j; j < n && j < 12; ++j) {
                address spender = handler.holders(j);
                assertEq(
                    token.allowance(owner, spender),
                    handler.ghostAllowance(owner, spender),
                    "allowance diverged from model"
                );
            }
        }
    }

    /// @dev Every success returned true and every failure reverted with exactly the expected error.
    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_NoUnexpectedOutcome() public view {
        assertEq(handler.unexpectedOutcomes(), 0);
    }

    /// @dev Nobody but the seed holder ever started with tokens, so no holder can have more than
    ///      the supply, and the token never holds ETH.
    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_NoBalanceExceedsSupplyAndNoEther() public view {
        uint256 n = handler.holderCount();
        for (uint256 i; i < n; ++i) {
            assertLe(token.balanceOf(handler.holders(i)), SUPPLY);
        }
        assertEq(address(token).balance, 0);
    }

    function afterInvariant() public view {
        // Guards against a vacuous campaign in which nothing happened.
        assertGt(handler.successes() + handler.expectedFailures(), 0);
    }
}
