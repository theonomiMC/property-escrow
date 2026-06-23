// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PropertyEscrowBaseTest} from "./P_BaseTest.t.sol";
import {PropertyEscrow} from "../../src/PropertyEscrow.sol";

contract PropertyEscrow_DepositTest is PropertyEscrowBaseTest {
    function test_DepositFunds_WithZeroCalculatedProtocolFee() public {
        PropertyEscrow.Milestone[] memory m = _createMilestones(1, 1);

        vm.prank(buyer);
        uint256 id = escrow.createAgreement(buyer, seller, inspector, uint32(block.timestamp + 10 days), defaultFee, m);

        vm.prank(buyer);
        escrow.depositFunds(id);
    }

    function test_DepositFunds_Reverts_NotBuyer() public {
        uint256 id = _createAgreementOnly(buyer, seller, inspector, uint32(defaultDeadline), defaultFee, 1, 300e6);
        vm.prank(inspector);
        vm.expectRevert(PropertyEscrow.Unauthorized.selector);
        escrow.depositFunds(id);
    }

    function test_DepositFunds_Reverts_InvalidState() public givenFundedAgreement {
        vm.prank(buyer);
        vm.expectRevert(PropertyEscrow.InvalidState.selector);
        escrow.depositFunds(defaultAgreementId);
    }

    function test_DepositFunds_Reverts_NonExistingAgreement() public {
        _createAgreementOnly(buyer, seller, inspector, uint32(defaultDeadline), defaultFee, 1, 300e6);
        vm.prank(address(0));
        vm.expectRevert(PropertyEscrow.AgreementNotFound.selector);
        escrow.depositFunds(9);
    }
}
