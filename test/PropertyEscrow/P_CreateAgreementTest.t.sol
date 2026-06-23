// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PropertyEscrowBaseTest} from "./P_BaseTest.t.sol";
import {PropertyEscrow} from "../../src/PropertyEscrow.sol";

contract PropertyEscrow_CreateAgreementTest is PropertyEscrowBaseTest {
    function test_CreateAgreement_Success() public {
        PropertyEscrow.Milestone[] memory m = _createMilestones(1, 300e6);
        uint256 expectedId = 0;
        uint256 expectedTotalAmount = 300e6;

        vm.expectEmit(true, true, true, true);
        emit PropertyEscrow.AgreementCreated(expectedId, buyer, seller, defaultFee, expectedTotalAmount);

        vm.prank(buyer);
        uint256 id = escrow.createAgreement(buyer, seller, inspector, uint32(block.timestamp + 10 days), defaultFee, m);

        assertEq(id, expectedId);
        assertEq(_getAgrTotalAmount(id), expectedTotalAmount);
    }

    function test_CreateAgreement_Revert_InvalidDeadline_TooShort() public {
        PropertyEscrow.Milestone[] memory m = _createMilestones(1, 300e6);
        uint32 tooShortDeadline = uint32(escrow.MIN_DEADLINE_DURATION() - 1 hours);

        vm.prank(buyer);
        vm.expectRevert(PropertyEscrow.InvalidDeadline.selector);
        escrow.createAgreement(buyer, seller, inspector, tooShortDeadline, defaultFee, m);
    }

    function test_CreateAgreement_Revert_InvalidDeadline_TooLong() public {
        PropertyEscrow.Milestone[] memory m = _createMilestones(1, 300e6);
        uint32 tooShortDeadline = uint32(escrow.MAX_DEADLINE_DURATION() + 1 hours);

        vm.prank(buyer);
        vm.expectRevert(PropertyEscrow.InvalidDeadline.selector);
        escrow.createAgreement(buyer, seller, inspector, tooShortDeadline, defaultFee, m);
    }

    function test_CreateAgreement_Revert_ZeroAddress() public {
        PropertyEscrow.Milestone[] memory m = _createMilestones(1, 500e6);
        vm.startPrank(seller);

        vm.expectRevert(PropertyEscrow.ZeroAddress.selector);
        escrow.createAgreement(address(0), seller, inspector, uint32(block.timestamp + 10 days), defaultFee, m);

        vm.expectRevert(PropertyEscrow.ZeroAddress.selector);
        escrow.createAgreement(buyer, address(0), inspector, uint32(block.timestamp + 10 days), defaultFee, m);

        vm.expectRevert(PropertyEscrow.ZeroAddress.selector);
        escrow.createAgreement(buyer, seller, address(0), uint32(block.timestamp + 10 days), defaultFee, m);

        vm.stopPrank();
    }

    function test_CreateAgreement_Revert_ZeroInspectorFee() public {
        PropertyEscrow.Milestone[] memory m = _createMilestones(1, 500e6);
        vm.prank(buyer);
        vm.expectRevert(PropertyEscrow.InvalidFee.selector);
        escrow.createAgreement(buyer, seller, inspector, uint32(defaultDeadline), 0, m);
    }

    function test_CreateAgreement_Revert_ZeroMilestone() public {
        PropertyEscrow.Milestone[] memory m = _createMilestones(0, 0);
        vm.prank(buyer);
        vm.expectRevert(PropertyEscrow.InvalidMilestones.selector);
        escrow.createAgreement(buyer, seller, inspector, uint32(defaultDeadline), defaultFee, m);
    }

    function test_CreateAgreement_Revert_TooLongMilestones() public {
        PropertyEscrow.Milestone[] memory m = _createMilestones(16, 500);
        vm.prank(buyer);
        vm.expectRevert(PropertyEscrow.InvalidMilestones.selector);
        escrow.createAgreement(buyer, seller, inspector, uint32(defaultDeadline), defaultFee, m);
    }

    function test_CreateAgreement_Revert_ZeroMilestoneAmount() public {
        PropertyEscrow.Milestone[] memory m = _createMilestones(1, 0);
        vm.prank(buyer);
        vm.expectRevert(PropertyEscrow.ZeroAmount.selector);
        escrow.createAgreement(buyer, seller, inspector, uint32(defaultDeadline), defaultFee, m);
    }

    function test_CreateAgreement_Revert_AddressValidations() public {
        PropertyEscrow.Milestone[] memory m = _createMilestones(1, 500e6);

        vm.prank(unauthorizedUser);
        vm.expectRevert(PropertyEscrow.Unauthorized.selector);
        escrow.createAgreement(buyer, seller, inspector, uint32(block.timestamp + 10 days), defaultFee, m);

        vm.prank(seller);
        vm.expectRevert(PropertyEscrow.Unauthorized.selector);
        escrow.createAgreement(buyer, buyer, inspector, uint32(block.timestamp + 10 days), defaultFee, m);

        vm.prank(seller);
        vm.expectRevert(PropertyEscrow.InvalidAddress.selector);
        escrow.createAgreement(buyer, seller, seller, uint32(block.timestamp + 10 days), defaultFee, m);

        vm.prank(seller);
        vm.expectRevert(PropertyEscrow.ZeroAddress.selector);
        escrow.createAgreement(buyer, seller, address(0), uint32(block.timestamp + 10 days), defaultFee, m);
    }
}
