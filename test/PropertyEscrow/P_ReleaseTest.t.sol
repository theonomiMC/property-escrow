// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PropertyEscrowBaseTest} from "./P_BaseTest.t.sol";
import {PropertyEscrow} from "../../src/PropertyEscrow.sol";

contract PropertyEscrow_ReleaseTest is PropertyEscrowBaseTest {
    function test_ReleaseFunds_Success_StandardMilestone() public givenFundedAgreement {
        _approveFrom(buyer, defaultAgreementId, 0);
        _approveFrom(inspector, defaultAgreementId, 0);

        uint256 sellerBalanceBefore = usdc.balanceOf(seller);

        vm.expectEmit(true, true, true, true);
        emit PropertyEscrow.FundsReleased(defaultAgreementId, 0, 500e6);

        vm.prank(seller);
        escrow.releaseFunds(defaultAgreementId, 0);

        assertEq(usdc.balanceOf(seller), sellerBalanceBefore + 500e6);
        assertEq(usdc.balanceOf(inspector), 0);
    }

    function test_ReleaseFunds_Success_SellerInspector() public givenFundedAgreement {
        _approveFrom(inspector, defaultAgreementId, 0);
        _approveFrom(seller, defaultAgreementId, 0);

        vm.prank(seller);
        escrow.releaseFunds(defaultAgreementId, 0);

        assertEq(usdc.balanceOf(seller), 500e6);
        assertEq(usdc.balanceOf(inspector), 0); // not the last milestone
    }

    function test_ReleaseFunds_Revert_InsufficientApprovals() public givenFundedAgreement {
        _approveFrom(inspector, defaultAgreementId, 0);

        vm.prank(seller);
        vm.expectRevert(PropertyEscrow.InsufficientApprovals.selector);
        escrow.releaseFunds(defaultAgreementId, 0);
    }

    function test_ReleaseFunds_AutoComplete_LastMilestone() public givenFundedAgreement {
        _approveFrom(inspector, defaultAgreementId, 0);
        _approveFrom(seller, defaultAgreementId, 0);

        vm.prank(seller);
        escrow.releaseFunds(defaultAgreementId, 0);

        _approveFrom(inspector, defaultAgreementId, 1);
        _approveFrom(seller, defaultAgreementId, 1);

        vm.prank(seller);
        escrow.releaseFunds(defaultAgreementId, 1);

        PropertyEscrow.State finalState = _getState(defaultAgreementId);
        assertEq(uint256(finalState), uint256(PropertyEscrow.State.Completed));
        assertEq(usdc.balanceOf(seller), 1000e6);
        assertEq(usdc.balanceOf(inspector), defaultFee);
    }

    function test_ReleaseFunds_Revert_Unauthorized() public givenFundedAgreement {
        _approveFrom(buyer, defaultAgreementId, 0);
        _approveFrom(seller, defaultAgreementId, 0);

        vm.prank(unauthorizedUser);
        vm.expectRevert(PropertyEscrow.Unauthorized.selector);
        escrow.releaseFunds(defaultAgreementId, 0);
    }

    function test_ReleaseFunds_Revert_AlreadyCompleted() public givenFundedAgreement {
        _approveFrom(buyer, defaultAgreementId, 0);
        _approveFrom(seller, defaultAgreementId, 0);

        vm.prank(seller);
        escrow.releaseFunds(defaultAgreementId, 0); // პირველი წარმატებული გატანა

        vm.prank(seller);
        vm.expectRevert(PropertyEscrow.AlreadyCompleted.selector);
        escrow.releaseFunds(defaultAgreementId, 0); // მეორე მცდელობა იმავე ეტაპზე
    }

    function test_ReleaseFunds_Revert_InvalidIndex() public givenFundedAgreement {
        vm.prank(seller);
        vm.expectRevert(PropertyEscrow.InvalidIndex.selector);
        escrow.releaseFunds(defaultAgreementId, 99);
    }

    function test_ReleaseFunds_Revert_InvalidAgreementId() public givenFundedAgreement {
        vm.prank(seller);
        vm.expectRevert(PropertyEscrow.AgreementNotFound.selector);
        escrow.releaseFunds(99, 0);
    }

    function test_ReleaseFunds_Revert_InvalidState_Created() public {
        uint256 id = _createAgreementOnly(buyer, seller, inspector, uint32(block.timestamp + 10 days), 100e6, 1, 500e6);

        vm.prank(seller);
        vm.expectRevert(PropertyEscrow.InvalidState.selector);
        escrow.releaseFunds(id, 0);
    }

    // Approve
    function test_ApproveMilestone_Revert_AlreadyCompleted() public givenFundedAgreement {
        _approveFrom(buyer, defaultAgreementId, 0);
        _approveFrom(inspector, defaultAgreementId, 0);

        vm.prank(seller);
        escrow.releaseFunds(defaultAgreementId, 0); // it's completed

        vm.prank(buyer);
        vm.expectRevert(PropertyEscrow.AlreadyCompleted.selector);
        escrow.approveMilestone(defaultAgreementId, 0);
    }

    function test_ApproveMilestone_Revert_Unauthorized() public givenFundedAgreement {
        vm.prank(unauthorizedUser);
        vm.expectRevert(PropertyEscrow.Unauthorized.selector);
        escrow.approveMilestone(defaultAgreementId, 0);
    }

    function test_ApproveMilestone_Revert_DoublApproval() public givenFundedAgreement {
        _approveFrom(buyer, defaultAgreementId, 0);

        vm.prank(buyer);
        vm.expectRevert(PropertyEscrow.MilestoneAlreadyApproved.selector);
        escrow.approveMilestone(defaultAgreementId, 0);

        _approveFrom(seller, defaultAgreementId, 0);

        vm.prank(seller);
        vm.expectRevert(PropertyEscrow.MilestoneAlreadyApproved.selector);
        escrow.approveMilestone(defaultAgreementId, 0);
    }

    function test_ApproveMilestone_Revert_InvalidAgreementId() public givenFundedAgreement {
        vm.prank(buyer);
        vm.expectRevert(PropertyEscrow.AgreementNotFound.selector);
        escrow.approveMilestone(99, 0);
    }

    function test_ApproveMilestone_Revert_InvalidState() public givenFundedAgreement {
        for (uint256 i = 0; i < 2; i++) {
            _approveFrom(buyer, defaultAgreementId, i);
            _approveFrom(inspector, defaultAgreementId, i);

            vm.prank(seller);
            escrow.releaseFunds(defaultAgreementId, i);
        }

        PropertyEscrow.State currentState = _getState(0);
        assertEq(uint256(currentState), uint256(PropertyEscrow.State.Completed));

        vm.prank(seller);
        vm.expectRevert(PropertyEscrow.InvalidState.selector);
        escrow.approveMilestone(defaultAgreementId, 0);
    }

    function test_ApproveMilestone_Revert_UnauthorizedUser() public givenFundedAgreement {
        vm.prank(unauthorizedUser);
        vm.expectRevert(PropertyEscrow.Unauthorized.selector);
        escrow.approveMilestone(defaultAgreementId, 0);
    }

    function test_ApproveMilestone_Revert_AgreementNotFound() public {
        vm.prank(seller);
        vm.expectRevert(PropertyEscrow.AgreementNotFound.selector);
        escrow.approveMilestone(9, 0);
    }
}
