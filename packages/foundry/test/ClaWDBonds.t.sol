// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../contracts/ClaWDBonds.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockCLAWD is ERC20 {
    constructor() ERC20("CLAWD", "CLAWD") {
        _mint(msg.sender, 1_000_000_000e18);
    }
    function mint(address to, uint256 amt) external { _mint(to, amt); }
}

contract ClaWDBondsTest is Test {
    ClaWDBonds bonds;
    MockCLAWD token;
    address owner = address(0x1);
    address alice = address(0x2);
    address bob   = address(0x3);

    function setUp() public {
        vm.startPrank(owner);
        token = new MockCLAWD();
        bonds = new ClaWDBonds(address(token), owner);
        token.approve(address(bonds), 10_000_000e18);
        bonds.fundTreasury(1_000_000e18);
        vm.stopPrank();

        token.mint(alice, 1_000_000e18);
        token.mint(bob, 1_000_000e18);
    }

    function test_InitialState() public view {
        assertEq(bonds.totalTreasuryFunded(), 1_000_000e18);
        assertEq(bonds.availableTreasury(), 1_000_000e18);
        assertEq(bonds.bondCounter(), 0);
    }

    function test_FundTreasury() public {
        vm.startPrank(owner);
        token.approve(address(bonds), 500_000e18);
        bonds.fundTreasury(500_000e18);
        vm.stopPrank();
        assertEq(bonds.totalTreasuryFunded(), 1_500_000e18);
    }

    function test_CreateBond24hr() public {
        vm.startPrank(alice);
        token.approve(address(bonds), 100_000e18);
        uint256 id = bonds.createBond(100_000e18, 0);
        vm.stopPrank();

        ClaWDBonds.Bond memory b = bonds.getBond(id);
        assertEq(b.amount, 100_000e18);
        assertEq(b.reward, 500e18); // 0.5%
        assertEq(b.maturityTimestamp, block.timestamp + 24 hours);
        assertFalse(b.claimed);
    }

    function test_CreateBond7day() public {
        vm.startPrank(alice);
        token.approve(address(bonds), 100_000e18);
        uint256 id = bonds.createBond(100_000e18, 1);
        vm.stopPrank();

        ClaWDBonds.Bond memory b = bonds.getBond(id);
        assertEq(b.reward, 2_000e18); // 2%
        assertEq(b.maturityTimestamp, block.timestamp + 7 days);
    }

    function test_ClaimAfterMaturity() public {
        vm.startPrank(alice);
        token.approve(address(bonds), 100_000e18);
        uint256 id = bonds.createBond(100_000e18, 0);
        vm.stopPrank();

        vm.warp(block.timestamp + 24 hours + 1);

        uint256 balBefore = token.balanceOf(alice);
        vm.prank(alice);
        bonds.claimBond(id);
        assertEq(token.balanceOf(alice) - balBefore, 100_500e18);
        assertTrue(bonds.getBond(id).claimed);
    }

    function test_RevertClaimBeforeMaturity() public {
        vm.startPrank(alice);
        token.approve(address(bonds), 100_000e18);
        uint256 id = bonds.createBond(100_000e18, 0);
        vm.stopPrank();

        vm.expectRevert(ClaWDBonds.BondNotMatured.selector);
        vm.prank(alice);
        bonds.claimBond(id);
    }

    function test_RevertClaimTwice() public {
        vm.startPrank(alice);
        token.approve(address(bonds), 100_000e18);
        uint256 id = bonds.createBond(100_000e18, 0);
        vm.stopPrank();

        vm.warp(block.timestamp + 24 hours + 1);
        vm.prank(alice);
        bonds.claimBond(id);

        vm.expectRevert(ClaWDBonds.BondAlreadyClaimed.selector);
        vm.prank(alice);
        bonds.claimBond(id);
    }

    function test_RevertClaimWrongUser() public {
        vm.startPrank(alice);
        token.approve(address(bonds), 100_000e18);
        uint256 id = bonds.createBond(100_000e18, 0);
        vm.stopPrank();

        vm.warp(block.timestamp + 24 hours + 1);
        vm.expectRevert(ClaWDBonds.NotBondOwner.selector);
        vm.prank(bob);
        bonds.claimBond(id);
    }

    function test_RevertInsufficientTreasury() public {
        // 2% of 100M = 2M, but treasury only has 1M
        vm.startPrank(alice);
        token.mint(alice, 100_000_000e18);
        token.approve(address(bonds), 100_000_000e18);
        vm.expectRevert(ClaWDBonds.InsufficientTreasuryBalance.selector);
        bonds.createBond(100_000_000e18, 1);
        vm.stopPrank();
    }

    function test_WithdrawTreasury() public {
        vm.prank(owner);
        bonds.withdrawTreasury(500_000e18);
        assertEq(bonds.availableTreasury(), 500_000e18);
    }

    function test_RevertWithdrawCommitted() public {
        vm.startPrank(alice);
        token.approve(address(bonds), 100_000e18);
        bonds.createBond(100_000e18, 1); // commits 2K reward
        vm.stopPrank();

        vm.expectRevert(ClaWDBonds.InsufficientWithdrawableBalance.selector);
        vm.prank(owner);
        bonds.withdrawTreasury(1_000_000e18); // full treasury but 2K committed
    }

    function test_GetUserBonds() public {
        vm.startPrank(alice);
        token.approve(address(bonds), 200_000e18);
        bonds.createBond(100_000e18, 0);
        bonds.createBond(100_000e18, 1);
        vm.stopPrank();

        uint256[] memory ids = bonds.getUserBonds(alice);
        assertEq(ids.length, 2);
    }

    function test_IsBondClaimable() public {
        vm.startPrank(alice);
        token.approve(address(bonds), 100_000e18);
        uint256 id = bonds.createBond(100_000e18, 0);
        vm.stopPrank();

        assertFalse(bonds.isBondClaimable(id));
        vm.warp(block.timestamp + 24 hours);
        assertTrue(bonds.isBondClaimable(id));

        vm.prank(alice);
        bonds.claimBond(id);
        assertFalse(bonds.isBondClaimable(id));
    }

    function test_ContractStats() public {
        vm.startPrank(alice);
        token.approve(address(bonds), 100_000e18);
        bonds.createBond(100_000e18, 0);
        vm.stopPrank();

        (uint256 total, uint256 avail, uint256 committed, uint256 count) = bonds.getContractStats();
        assertEq(total, 1_000_000e18);
        assertEq(committed, 500e18);
        assertEq(avail, 1_000_000e18 - 500e18);
        assertEq(count, 1);
    }

    function test_RevertInvalidTermIndex() public {
        vm.startPrank(alice);
        token.approve(address(bonds), 100_000e18);
        vm.expectRevert(ClaWDBonds.InvalidTermIndex.selector);
        bonds.createBond(100_000e18, 2);
        vm.stopPrank();
    }

    function test_RevertZeroAmount() public {
        vm.expectRevert(ClaWDBonds.ZeroAmount.selector);
        vm.prank(alice);
        bonds.createBond(0, 0);
    }

    // Fuzz test: reward calculation is always correct
    function testFuzz_RewardCalculation(uint256 amount, uint8 termIndex) public {
        termIndex = uint8(bound(termIndex, 0, 1));
        amount = bound(amount, 1e18, 50_000_000e18); // reasonable range

        uint256 rate = termIndex == 0 ? 50 : 200;
        uint256 expectedReward = (amount * rate) / 10000;

        // Only create if treasury can cover
        if (expectedReward <= bonds.availableTreasury()) {
            vm.startPrank(alice);
            token.mint(alice, amount);
            token.approve(address(bonds), amount);
            uint256 id = bonds.createBond(amount, termIndex);
            vm.stopPrank();

            ClaWDBonds.Bond memory b = bonds.getBond(id);
            assertEq(b.reward, expectedReward);
        }
    }
}
