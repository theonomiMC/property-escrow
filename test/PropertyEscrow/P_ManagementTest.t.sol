// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PropertyEscrowBaseTest} from "./P_BaseTest.t.sol";
import {PropertyEscrow} from "../../src/PropertyEscrow.sol";

contract PropertyEscrow_ManagementTest is PropertyEscrowBaseTest {
    function test_ExtendDeadline_Success_BothPartiesAgree() public givenFundedAgreement {
        uint256 newDeadline = block.timestamp + 30 days;

        vm.prank(buyer);
        escrow.extendDeadline(defaultAgreementId, uint32(newDeadline));

        vm.prank(seller);
        escrow.extendDeadline(defaultAgreementId, uint32(newDeadline));

        (,, uint32 currentDeadline,,,,,,,,,) = escrow.agreements(defaultAgreementId);

        assertEq(currentDeadline, uint32(newDeadline));
    }

    function test_ExtendDeadline_Revert_OnlyOneBuyerProposed() public givenFundedAgreement {
        uint256 newDeadline = block.timestamp + 30 days;

        vm.prank(buyer);
        escrow.extendDeadline(defaultAgreementId, uint32(newDeadline));

        (,, uint32 currentDeadline,,,,,,,,,) = escrow.agreements(defaultAgreementId);

        assertNotEq(currentDeadline, uint32(newDeadline));
    }

    function test_ExtendDeadline_OnlySellerProposed() public givenFundedAgreement {
        uint256 newDeadline = block.timestamp + 30 days;

        vm.prank(seller);
        escrow.extendDeadline(defaultAgreementId, uint32(newDeadline));

        (,, uint32 currentDeadline,,,,,,,,,) = escrow.agreements(defaultAgreementId);

        assertNotEq(currentDeadline, uint32(newDeadline));
    }

    function test_ExtendDeadline_Revert_InvalidDeadline() public givenFundedAgreement {
        uint256 newDeadline1 = block.timestamp + 366 days;
        uint256 newDeadline2 = block.timestamp + 10 days;

        vm.prank(seller);
        vm.expectRevert(PropertyEscrow.InvalidDeadline.selector);
        escrow.extendDeadline(defaultAgreementId, uint32(newDeadline1));

        vm.prank(seller);
        vm.expectRevert(PropertyEscrow.InvalidDeadline.selector);
        escrow.extendDeadline(defaultAgreementId, uint32(newDeadline2));
    }

    function test_ExtendDeadline_Revert_InvalidState() public {
        uint256 id = _createAgreementOnly(buyer, seller, inspector, uint32(defaultDeadline), defaultFee, 1, 100e6);

        uint256 newDeadline = block.timestamp + 30 days;
        vm.prank(buyer);
        vm.expectRevert(PropertyEscrow.InvalidState.selector);
        escrow.extendDeadline(id, uint32(newDeadline));
    }

    function test_ExtendDeadline_Revert_Unuathorized() public givenFundedAgreement {
        uint256 newDeadline = block.timestamp + 30 days;

        vm.prank(address(0x123455));
        vm.expectRevert(PropertyEscrow.Unauthorized.selector);
        escrow.extendDeadline(defaultAgreementId, uint32(newDeadline));
    }

    // Change Inspector
    function test_ChangeInspector_Success() public givenFundedAgreement {
        address newInspector = makeAddr("New Inspector");

        vm.prank(address(this));
        escrow.changeInspector(defaultAgreementId, newInspector);

        (,,,,,,,, address currentInspector,,,) = escrow.agreements(defaultAgreementId);

        assertEq(currentInspector, newInspector);
    }

    function test_ChangeInspector_Revert_NotOwner() public givenFundedAgreement {
        address newInspector = makeAddr("New Inspector");

        vm.prank(buyer);
        vm.expectRevert();
        escrow.changeInspector(defaultAgreementId, newInspector);
    }

    function test_ChangeInspector_Revert_onBuyerOrSeller() public givenFundedAgreement {
        vm.prank(address(this));
        vm.expectRevert(PropertyEscrow.InvalidAddress.selector);
        escrow.changeInspector(defaultAgreementId, buyer);

        vm.prank(address(this));
        vm.expectRevert(PropertyEscrow.InvalidAddress.selector);
        escrow.changeInspector(defaultAgreementId, seller);
    }

    function test_ChangeInspector_Revert_onEmptyAddress() public givenFundedAgreement {
        vm.prank(address(this));
        vm.expectRevert(PropertyEscrow.ZeroAddress.selector);
        escrow.changeInspector(defaultAgreementId, address(0));
    }

    function test_ChangeInspector_Revert_onIncorrectState() public givenFundedAgreement {
        for (uint256 i = 0; i < 2; i++) {
            _approveFrom(buyer, defaultAgreementId, i);
            _approveFrom(inspector, defaultAgreementId, i);

            vm.prank(seller);
            escrow.releaseFunds(defaultAgreementId, i);
        }

        vm.prank(address(this));
        vm.expectRevert(PropertyEscrow.InvalidState.selector);
        escrow.changeInspector(defaultAgreementId, address(0x1234));
    }

    function test_ChangeInspector_Revert_onNonExistingAgreement() public givenFundedAgreement {
        vm.prank(address(this));
        vm.expectRevert(PropertyEscrow.AgreementNotFound.selector);
        escrow.changeInspector(99, address(0x1234));
    }

    function test_ProtocolFeeUpdate_Success() public {
        uint256 currentFee = escrow.protocolFeeBps();
        uint256 newProtocol = 200;

        assertEq(escrow.protocolFeeBps(), currentFee);

        vm.prank(escrow.owner());
        escrow.updateProtocolFee(newProtocol);

        assertEq(escrow.protocolFeeBps(), newProtocol);
    }

    function test_ProtocolFeeUpdate_RevertsOnZeroAmount() public {
        vm.prank(escrow.owner());
        vm.expectRevert(PropertyEscrow.ZeroAmount.selector);
        escrow.updateProtocolFee(0);
    }

    function test_ProtocolFeeUpdate_RevertsOnExceededCap() public {
        vm.prank(escrow.owner());
        vm.expectRevert(PropertyEscrow.ProtocolFeeTooHigh.selector);
        escrow.updateProtocolFee(1001);
    }

    function test_ProtocolFeeUpdate_RevertsOnUnauthorizedUser() public {
        vm.prank(buyer);
        vm.expectRevert();
        escrow.updateProtocolFee(200);
    }

    function test_AuthorizeUpgrade_Revert_NotOwner() public {
        PropertyEscrow newImpl = new PropertyEscrow();

        vm.prank(unauthorizedUser);
        vm.expectRevert(); // OwnableUnauthorizedAccount
        escrow.upgradeToAndCall(address(newImpl), "");
    }

    function test_Initialize_Revert_ZeroAddress() public {
        PropertyEscrow impl = new PropertyEscrow();
        vm.expectRevert();
        impl.initialize(address(0), 100, address(this));
    }

    function test_Pause_Revert_CreateAgreementWhenPaused() public {
        PropertyEscrow.Milestone[] memory m = new PropertyEscrow.Milestone[](1);
        m[0].amount = uint128(100e6);

        vm.prank(address(this));
        escrow.pause();

        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        escrow.createAgreement(buyer, seller, inspector, uint32(defaultDeadline), defaultFee, m);
    }

    function test_Pause_Revert_DepositWhenPaused() public givenFundedAgreement {
        vm.prank(address(this));
        escrow.pause();

        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        escrow.depositFunds(defaultAgreementId);
    }

    function test_Pause_Revert_ApproveMilstoneWhenPaused() public givenFundedAgreement {
        vm.prank(address(this));
        escrow.pause();

        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        escrow.approveMilestone(defaultAgreementId, 0);
    }

    function test_Pause_Revert_ReleaseWhenPaused() public givenFundedAgreement {
        _approveFrom(buyer, defaultAgreementId, 0);
        _approveFrom(inspector, defaultAgreementId, 0);

        vm.prank(address(this));
        escrow.pause();

        vm.prank(seller);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        escrow.releaseFunds(defaultAgreementId, 0);
    }
}
