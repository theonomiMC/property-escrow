// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PropertyEscrowBaseTest} from "./P_BaseTest.t.sol";
import {PropertyEscrow} from "../../src/PropertyEscrow.sol";

contract PropertyEscro_CancelAgreementTest is PropertyEscrowBaseTest {
    function test_CancelAgreement_Revert_InvalidState() public givenFundedAgreement {
        vm.prank(buyer);
        vm.expectRevert(PropertyEscrow.InvalidState.selector);
        escrow.cancelAgreement(defaultAgreementId);
    }

    function test_CancelAgreement_Success() public {
        vm.startPrank(seller);
        PropertyEscrow.Milestone[] memory m = _createMilestones(1, 500e6);
        escrow.createAgreement(buyer, seller, inspector, uint32(block.timestamp + 10 days), 100e6, m);

        escrow.cancelAgreement(0);
        vm.stopPrank();

        PropertyEscrow.State currentState = _getState(0);
        assertEq(uint256(currentState), uint256(PropertyEscrow.State.Cancelled));
    }

    function test_CancelAgreement_Revert_Unauthorized() public {
        _createAgreementOnly(buyer, seller, inspector, uint32(defaultDeadline), defaultFee, 1, 300e6);

        vm.prank(unauthorizedUser);
        vm.expectRevert(PropertyEscrow.Unauthorized.selector);
        escrow.cancelAgreement(defaultAgreementId);
    }
}
