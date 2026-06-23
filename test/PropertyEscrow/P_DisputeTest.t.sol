// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PropertyEscrowBaseTest} from "./P_BaseTest.t.sol";
import {PropertyEscrow} from "../../src/PropertyEscrow.sol";

contract PropertyEscrow_DisputeTest is PropertyEscrowBaseTest {
    function test_ResolveDispute_Success_Split() public givenDisputedAgreement {
        uint256 buyerBalanceBeforeDispute = usdc.balanceOf(buyer);
        uint256 sellerBalanceBeforeDispute = usdc.balanceOf(seller);

        vm.prank(inspector);
        escrow.resolveDispute(defaultAgreementId, 400e6, 600e6);

        assertEq(buyerBalanceBeforeDispute + 400e6, usdc.balanceOf(buyer));
        assertEq(usdc.balanceOf(inspector), defaultFee);
        assertEq(sellerBalanceBeforeDispute + 600e6, usdc.balanceOf(seller));
    }

    function test_ResolveDispute_Revert_invalidState() public givenFundedAgreement {
        vm.prank(inspector);
        vm.expectRevert(PropertyEscrow.InvalidState.selector);
        escrow.resolveDispute(defaultAgreementId, 400e6, 600e6);
    }

    function test_ResolveDispute_Revert_NotInspector() public givenFundedAgreement {
        vm.prank(buyer);
        vm.expectRevert(PropertyEscrow.Unauthorized.selector);
        escrow.resolveDispute(defaultAgreementId, 400e6, 600e6);
    }

    function test_ResolveDispute_Revert_InvalidDistribution() public givenDisputedAgreement {
        vm.prank(inspector);
        vm.expectRevert(PropertyEscrow.InvalidDistribution.selector);
        escrow.resolveDispute(defaultAgreementId, 400e6, 500e6);
    }

    function test_ResolveDispute_Revert_InspectorCannotStealEarnedFunds() public givenFundedAgreement {
        _approveFrom(buyer, defaultAgreementId, 0);
        _approveFrom(seller, defaultAgreementId, 0); // seller earnd 500e6

        vm.prank(buyer);
        escrow.openDispute(defaultAgreementId);

        vm.prank(inspector);
        vm.expectRevert(PropertyEscrow.InvalidDistribution.selector);
        escrow.resolveDispute(defaultAgreementId, 600e6, 400e6);
    }

    function test_OpenDispute_Success() public givenDisputedAgreement {
        PropertyEscrow.State currentState = _getState(defaultAgreementId);
        assertEq(uint256(currentState), uint256(PropertyEscrow.State.Disputed));
    }

    function test_OpenDispute_Revert_DeadlineExpired() public givenFundedAgreement {
        vm.warp(block.timestamp + defaultDeadline + 1 days);

        vm.prank(buyer);
        vm.expectRevert(PropertyEscrow.DeadlineExpired.selector);
        escrow.openDispute(defaultAgreementId);
    }

    function test_OpenDispute_Revert_Unauthorized() public givenFundedAgreement {
        vm.prank(address(0xDEAD));
        vm.expectRevert(PropertyEscrow.Unauthorized.selector);
        escrow.openDispute(defaultAgreementId);
    }

    function test_ExecuteDisputeTimeout_Success() public givenFundedAgreement {
        _approveFrom(buyer, defaultAgreementId, 0);
        _approveFrom(seller, defaultAgreementId, 0);

        uint256 buyerBalanceBefore = usdc.balanceOf(buyer);

        vm.prank(seller);
        escrow.releaseFunds(defaultAgreementId, 0);

        vm.prank(buyer);
        escrow.openDispute(defaultAgreementId);

        vm.warp(block.timestamp + escrow.DISPUTE_TIMEOUT() + 1 days);

        vm.prank(buyer);
        escrow.executeDisputeTimeout(defaultAgreementId);

        assertEq(usdc.balanceOf(seller), 500e6);
        assertEq(usdc.balanceOf(inspector), 0);
        assertEq(buyerBalanceBefore + 600e6, usdc.balanceOf(buyer));
    }

    function test_ExecuteDisputeTimeout_Revert_StillInTimeout() public givenDisputedAgreement {
        vm.prank(buyer);
        vm.expectRevert(PropertyEscrow.TimeoutNotReached.selector);
        escrow.executeDisputeTimeout(defaultAgreementId);
    }

    function test_ExecuteDisputeTimeout_Revert_Unauthorized() public givenDisputedAgreement {
        vm.prank(address(0xDEAD));
        vm.expectRevert(PropertyEscrow.Unauthorized.selector);
        escrow.executeDisputeTimeout(defaultAgreementId);
    }

    function test_ExecuteDisputeTimeout_Seller_KeepsUnreleasedFunds() public givenFundedAgreement {
        _approveFrom(buyer, defaultAgreementId, 0);
        _approveFrom(seller, defaultAgreementId, 0);

        vm.prank(buyer);
        escrow.openDispute(defaultAgreementId);

        vm.warp(block.timestamp + escrow.DISPUTE_TIMEOUT() + 1 days);

        vm.prank(buyer);
        escrow.executeDisputeTimeout(defaultAgreementId);

        PropertyEscrow.State finalState = _getState(defaultAgreementId);
        assertEq(uint256(finalState), uint256(PropertyEscrow.State.Funded));
    }

    function test_ExecuteDisputeTimeout_Revert_InvalidState() public givenFundedAgreement {
        vm.prank(buyer);
        vm.expectRevert(PropertyEscrow.InvalidState.selector);
        escrow.executeDisputeTimeout(defaultAgreementId);
    }
}
