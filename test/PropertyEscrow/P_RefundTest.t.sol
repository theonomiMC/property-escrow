// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PropertyEscrowBaseTest} from "./P_BaseTest.t.sol";
import {PropertyEscrow} from "../../src/PropertyEscrow.sol";

contract PropertyEscrow_RefundTest is PropertyEscrowBaseTest {
    function test_RefundFunds_Revert_BeforeDeadline() public givenFundedAgreement {
        _approveFrom(inspector, defaultAgreementId, 0);
        _approveFrom(seller, defaultAgreementId, 0);

        vm.prank(seller);
        escrow.releaseFunds(defaultAgreementId, 0);

        vm.prank(buyer);
        vm.expectRevert(PropertyEscrow.StillInDeadline.selector);
        escrow.refundFunds(defaultAgreementId);
    }

    function test_ExpectRevert_BuyerCannotStealEarnedFunds() public givenFundedAgreement {
        uint256 totalAmount = _getAgrTotalAmount(defaultAgreementId);
        uint256 buyerBalanceBefore = usdc.balanceOf(buyer);

        _approveFrom(buyer, defaultAgreementId, 0);
        _approveFrom(seller, defaultAgreementId, 0);

        // pass time
        vm.warp(block.timestamp + defaultDeadline + 1 days);

        vm.prank(buyer);
        escrow.refundFunds(defaultAgreementId);

        assertEq(usdc.balanceOf(buyer), buyerBalanceBefore + totalAmount / 2 + defaultFee / 2);
        assertEq(usdc.balanceOf(address(escrow)), totalAmount / 2);
        assertEq(usdc.balanceOf(seller), 0);

        PropertyEscrow.State currentState = _getState(defaultAgreementId);

        assertEq(uint256(currentState), uint256(PropertyEscrow.State.Funded));
    }

    function test_RefundFunds_Success_ReturnsUnallocatedFunds() public givenFundedAgreement {
        _approveFrom(inspector, defaultAgreementId, 0);
        _approveFrom(seller, defaultAgreementId, 0);

        vm.prank(seller);
        escrow.releaseFunds(defaultAgreementId, 0);

        uint256 buyerBalanceBeforeRefund = usdc.balanceOf(buyer);
        uint256 totalAmount = _getAgrTotalAmount(defaultAgreementId);

        vm.warp(block.timestamp + defaultDeadline + 1 days);

        vm.prank(buyer);
        escrow.refundFunds(defaultAgreementId);

        assertEq(buyerBalanceBeforeRefund + totalAmount / 2 + defaultFee / 2, usdc.balanceOf(buyer));
        assertEq(defaultFee / 2, usdc.balanceOf(inspector));
        assertEq(usdc.balanceOf(seller), totalAmount / 2);
    }

    function test_RefundFunds_Success_FullRefund() public givenFundedAgreement {
        uint256 buyerBalanceBefore = usdc.balanceOf(buyer);
        uint256 totalAmount = _getAgrTotalAmount(defaultAgreementId);

        vm.warp(block.timestamp + defaultDeadline + 1 days);

        vm.prank(buyer);
        escrow.refundFunds(defaultAgreementId);

        assertEq(usdc.balanceOf(buyer), buyerBalanceBefore + totalAmount + defaultFee);
        assertEq(usdc.balanceOf(inspector), 0);
        assertEq(usdc.balanceOf(seller), 0);

        PropertyEscrow.State currentState = _getState(defaultAgreementId);
        assertEq(uint256(currentState), uint256(PropertyEscrow.State.Refunded));
    }

    function test_RefundFunds_Revert_NotBuyer() public givenFundedAgreement {
        vm.warp(block.timestamp + defaultDeadline + 1 days);

        vm.prank(unauthorizedUser);
        vm.expectRevert(PropertyEscrow.Unauthorized.selector);
        escrow.refundFunds(defaultAgreementId);
    }

    function test_RefundFunds_Revert_InvalidState_Created() public {
        uint256 id =
            _createAgreementOnly(buyer, seller, inspector, uint32(block.timestamp + 10 days), defaultFee, 2, 500e6);

        vm.warp(block.timestamp + 11 days);

        vm.prank(buyer);
        vm.expectRevert(PropertyEscrow.InvalidState.selector);
        escrow.refundFunds(id);
    }

    function test_RefundFunds_Revert_ZeroAmountToRefund() public givenFundedAgreement {
        _approveFrom(buyer, defaultAgreementId, 0);
        _approveFrom(seller, defaultAgreementId, 0);
        _approveFrom(buyer, defaultAgreementId, 1);
        _approveFrom(seller, defaultAgreementId, 1);

        vm.warp(block.timestamp + defaultDeadline + 1 days);

        vm.prank(buyer);
        vm.expectRevert(PropertyEscrow.ZeroAmount.selector);
        escrow.refundFunds(defaultAgreementId);
    }
}
