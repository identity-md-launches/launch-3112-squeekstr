// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, Vm} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SQUEEKSTR} from "../src/SQUEEKSTR.sol";

/// @dev Deploys the token and performs the whole launch split in a single call, the way a factory
///      launch does it in one transaction, and reports what each recipient received.
contract OneCallLauncher {
    function launch(bytes32 salt, address distributor, address pool, address remainder, uint256 poolBps)
        external
        returns (SQUEEKSTR token, uint256 swarmGot, uint256 poolGot, uint256 remainderGot, uint256 left)
    {
        token = new SQUEEKSTR{salt: salt}();
        uint256 supply = token.totalSupply();
        uint256 swarm = supply / 10;
        uint256 poolAmount = supply * poolBps / 10_000;
        require(token.transfer(distributor, swarm), "swarm");
        require(token.transfer(pool, poolAmount), "pool");
        require(token.transfer(remainder, supply - swarm - poolAmount), "remainder");
        swarmGot = token.balanceOf(distributor);
        poolGot = token.balanceOf(pool);
        remainderGot = token.balanceOf(remainder);
        left = token.balanceOf(address(this));
    }
}

contract SQUEEKSTREdgeTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    SQUEEKSTR internal token;
    address internal alice;
    address internal bob;
    address internal spender;

    function setUp() public {
        alice = makeAddr("edge alice");
        bob = makeAddr("edge bob");
        spender = makeAddr("edge spender");
        token = new SQUEEKSTR();
    }

    // ---------------------------------------------------------------- deployment

    /// @dev Whoever deploys receives everything; tx.origin and every other address receive nothing.
    function testFuzz_DeployerReceivesWholeSupply(address deployer, address origin) public {
        vm.assume(deployer != address(0) && deployer.code.length == 0);
        vm.prank(deployer, origin);
        SQUEEKSTR fresh = new SQUEEKSTR();
        assertEq(fresh.totalSupply(), SUPPLY);
        assertEq(fresh.balanceOf(deployer), SUPPLY);
        if (origin != deployer) assertEq(fresh.balanceOf(origin), 0);
        assertEq(fresh.balanceOf(address(fresh)), 0);
    }

    /// @dev Exactly one event in the constructor: the mint Transfer. No Approval, no ownership event.
    function test_ConstructorEmitsOnlyTheMintEvent() public {
        vm.recordLogs();
        SQUEEKSTR fresh = new SQUEEKSTR();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(fresh));
        assertEq(logs[0].topics[0], IERC20.Transfer.selector);
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(address(this)))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
    }

    /// @dev The launch split in one transaction arrives exact for any pool share up to the 90% the
    ///      requester controls.
    /// forge-config: default.fuzz.runs = 512
    function testFuzz_OneCallLaunchSplitIsExact(uint256 rawPoolBps) public {
        uint256 poolBps = bound(rawPoolBps, 0, 9_000);
        OneCallLauncher launcher = new OneCallLauncher();
        address distributor = makeAddr("launch distributor");
        address pool = makeAddr("launch pool");
        address remainder = makeAddr("launch remainder");
        (SQUEEKSTR launched, uint256 swarmGot, uint256 poolGot, uint256 remainderGot, uint256 left) =
            launcher.launch(bytes32(poolBps), distributor, pool, remainder, poolBps);
        assertEq(swarmGot, SUPPLY / 10);
        assertEq(poolGot, SUPPLY * poolBps / 10_000);
        assertEq(swarmGot + poolGot + remainderGot, SUPPLY);
        assertEq(left, 0);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    /// @dev The same salt from the same deployer cannot produce a second token (and a second supply).
    function test_RevertRedeployAtSameCreate2Address() public {
        OneCallLauncher launcher = new OneCallLauncher();
        address d = makeAddr("d");
        address p = makeAddr("p");
        address r = makeAddr("r");
        launcher.launch(bytes32(uint256(7)), d, p, r, 5_000);
        vm.expectRevert();
        launcher.launch(bytes32(uint256(7)), d, p, r, 5_000);
    }

    // ---------------------------------------------------------------- zero address failure paths

    function test_RevertTransferFromZeroSender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        vm.prank(address(0));
        token.transfer(alice, 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RevertApproveFromZeroOwner() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(address(0));
        token.approve(spender, 1);
        assertEq(token.allowance(address(0), spender), 0);
    }

    /// @dev Burning by sending to the zero address is impossible, so supply cannot shrink either.
    function testFuzz_RevertTransferToZeroAnyAmount(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, 0, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), amount);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function testFuzz_RevertTransferFromToZeroWithInfiniteAllowance(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        token.approve(spender, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), amount);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.totalSupply(), SUPPLY);
    }

    // ---------------------------------------------------------------- allowance edges

    /// @dev Spending an allowance updates storage without emitting Approval (OpenZeppelin v5),
    ///      and emits exactly the Transfer.
    function test_TransferFromEmitsOnlyTransfer() public {
        token.approve(spender, 50 ether);
        vm.recordLogs();
        vm.prank(spender);
        token.transferFrom(address(this), alice, 20 ether);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].topics[0], IERC20.Transfer.selector);
        assertEq(token.allowance(address(this), spender), 30 ether);
    }

    /// @dev An allowance of max-1 is finite and does decrease.
    function test_AllowanceJustBelowMaxIsFinite() public {
        token.approve(spender, type(uint256).max - 1);
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), type(uint256).max - 2);
    }

    /// @dev Balance and allowance are checked independently: a spender with allowance above the
    ///      owner's balance hits the balance error, and the allowance is not consumed.
    function testFuzz_RevertTransferFromOverBalance(uint256 rawHeld, uint256 rawAmount) public {
        uint256 held = bound(rawHeld, 0, SUPPLY - 1);
        uint256 amount = bound(rawAmount, held + 1, SUPPLY);
        token.transfer(alice, held);
        vm.prank(alice);
        token.approve(spender, SUPPLY);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, held, amount)
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), SUPPLY);
        assertEq(token.balanceOf(alice), held);
        assertEq(token.balanceOf(bob), 0);
    }

    function testFuzz_RevertTransferFromOverAllowance(uint256 rawApproved, uint256 rawAmount) public {
        uint256 approved = bound(rawApproved, 0, SUPPLY - 1);
        uint256 amount = bound(rawAmount, approved + 1, SUPPLY);
        token.approve(spender, approved);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, amount);
        assertEq(token.allowance(address(this), spender), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    /// @dev Allowances are per (owner, spender): approving one pair changes no other pair.
    function testFuzz_ApproveIsIsolated(address owner, address s, address other, uint256 amount) public {
        vm.assume(owner != address(0) && s != address(0) && other != address(0));
        vm.assume(other != s && other != owner);
        vm.prank(owner);
        token.approve(s, amount);
        assertEq(token.allowance(owner, s), amount);
        assertEq(token.allowance(owner, other), 0);
        assertEq(token.allowance(s, owner), owner == s ? amount : 0);
        assertEq(token.allowance(other, s), 0);
    }

    /// @dev Two spends that sum to the allowance succeed; one more wei fails.
    function testFuzz_SplitSpendExhaustsAllowance(uint256 rawTotal, uint256 rawFirst) public {
        uint256 total = bound(rawTotal, 1, SUPPLY);
        uint256 first = bound(rawFirst, 0, total);
        token.approve(spender, total);
        vm.startPrank(spender);
        token.transferFrom(address(this), alice, first);
        token.transferFrom(address(this), bob, total - first);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
        token.transferFrom(address(this), bob, 1);
        vm.stopPrank();
        assertEq(token.balanceOf(alice) + token.balanceOf(bob), total);
        assertEq(token.balanceOf(address(this)), SUPPLY - total);
    }

    // ---------------------------------------------------------------- transfer edges

    /// @dev One wei above the balance fails at every balance level, and nothing moves.
    function testFuzz_RevertOneWeiOverBalance(uint256 rawHeld) public {
        uint256 held = bound(rawHeld, 0, SUPPLY);
        token.transfer(alice, held);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, held, held + 1)
        );
        vm.prank(alice);
        token.transfer(bob, held + 1);
        assertEq(token.balanceOf(alice), held);
        assertEq(token.balanceOf(bob), 0);
    }

    /// @dev Tokens sent to the token contract itself are accepted (and, with no rescue function,
    ///      stay there); supply is unchanged.
    function test_TransferToTokenContractIsAccepted() public {
        token.transfer(address(token), 1 ether);
        assertEq(token.balanceOf(address(token)), 1 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// @dev Moving the full supply around a chain of holders ends with the last one holding it all.
    function testFuzz_ChainOfTransfersPreservesSupply(address a, address b, address c) public {
        vm.assume(a != address(0) && b != address(0) && c != address(0));
        token.transfer(a, SUPPLY);
        vm.prank(a);
        token.transfer(b, SUPPLY);
        vm.prank(b);
        token.transfer(c, SUPPLY);
        assertEq(token.balanceOf(c), SUPPLY);
        if (c != a) assertEq(token.balanceOf(a), 0);
        if (c != b) assertEq(token.balanceOf(b), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// @dev No permit / EIP-2612 surface and no OZ v4 allowance helpers: those calls fail.
    function test_NoPermitOrLegacyAllowanceHelpers() public {
        bytes[] memory calls = new bytes[](5);
        calls[0] = abi.encodeWithSignature(
            "permit(address,address,uint256,uint256,uint8,bytes32,bytes32)",
            alice,
            spender,
            1,
            type(uint256).max,
            uint8(27),
            bytes32(0),
            bytes32(0)
        );
        calls[1] = abi.encodeWithSignature("nonces(address)", alice);
        calls[2] = abi.encodeWithSignature("DOMAIN_SEPARATOR()");
        calls[3] = abi.encodeWithSignature("increaseAllowance(address,uint256)", spender, 1);
        calls[4] = abi.encodeWithSignature("decreaseAllowance(address,uint256)", spender, 1);
        for (uint256 i; i < calls.length; ++i) {
            (bool ok,) = address(token).call(calls[i]);
            assertFalse(ok);
        }
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.allowance(address(this), spender), 0);
    }
}
