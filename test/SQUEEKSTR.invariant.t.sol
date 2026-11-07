// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SQUEEKSTR} from "../src/SQUEEKSTR.sol";

/// @dev A closed set of holders and a separate accounting model. Failed operations must leave
///      both balances and allowances unchanged; successful operations must match the model.
contract TokenHandler is Test {
    SQUEEKSTR public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(SQUEEKSTR token_, uint256 supply) {
        token = token_;
        actors[0] = makeAddr("invariant holder 0");
        actors[1] = makeAddr("invariant holder 1");
        actors[2] = makeAddr("invariant holder 2");
        actors[3] = makeAddr("invariant holder 3");
        expectedBalance[actors[0]] = supply;
    }

    function transfer(uint256 fromIndex, uint256 toIndex, uint256 rawAmount) external {
        address from = _actor(fromIndex);
        address to = _actor(toIndex);
        uint256 amount = bound(rawAmount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerIndex, uint256 spenderIndex, uint256 amount) external {
        address owner = _actor(ownerIndex);
        address spender = _actor(spenderIndex);
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 ownerIndex, uint256 spenderIndex, uint256 toIndex, uint256 rawAmount)
        external
    {
        address owner = _actor(ownerIndex);
        address spender = _actor(spenderIndex);
        address to = _actor(toIndex);
        uint256 approved = expectedAllowance[owner][spender];
        uint256 balance = expectedBalance[owner];
        uint256 amount = bound(rawAmount, 0, balance < approved ? balance : approved);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
        if (approved != type(uint256).max) expectedAllowance[owner][spender] -= amount;
    }

    function rejectOverBalance(uint256 fromIndex, uint256 toIndex) external {
        address from = _actor(fromIndex);
        address to = _actor(toIndex);
        uint256 balance = expectedBalance[from];
        uint256 amount = balance + 1;
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount)
        );
        vm.prank(from);
        token.transfer(to, amount);
    }

    function rejectOverAllowance(uint256 ownerIndex, uint256 spenderIndex, uint256 toIndex) external {
        address owner = _actor(ownerIndex);
        address spender = _actor(spenderIndex);
        address to = _actor(toIndex);
        uint256 approved = expectedAllowance[owner][spender];
        if (approved == type(uint256).max) return;
        uint256 amount = approved + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount
            )
        );
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
    }

    function _actor(uint256 index) private view returns (address) {
        return actors[index % actors.length];
    }
}

contract SQUEEKSTRInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    SQUEEKSTR internal token;
    TokenHandler internal handler;

    function setUp() public {
        token = new SQUEEKSTR();
        handler = new TokenHandler(token, SUPPLY);
        token.transfer(handler.actors(0), SUPPLY);

        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = TokenHandler.transfer.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.transferFrom.selector;
        selectors[3] = TokenHandler.rejectOverBalance.selector;
        selectors[4] = TokenHandler.rejectOverAllowance.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_TotalSupplyAndBalancesAreConserved() public view {
        assertEq(token.totalSupply(), SUPPLY);
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            sum += token.balanceOf(handler.actors(i));
        }
        assertEq(sum, SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
    }

    function invariant_BalancesAndAllowancesMatchIndependentModel() public view {
        for (uint256 i; i < 4; ++i) {
            address owner = handler.actors(i);
            assertEq(token.balanceOf(owner), handler.expectedBalance(owner));
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
    }
}
