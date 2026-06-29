// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";
import {PropertyEscrow} from "../../src/PropertyEscrow.sol";
import {MockUSDC} from "../../test/mock/MockUSDC.sol";
import {Handler} from "./Handler.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract PropertyEscrowInvariant is StdInvariant, Test {
    PropertyEscrow public escrow;
    MockUSDC public usdc;
    Handler public handler;

    address buyer = makeAddr("buyer");
    address seller = makeAddr("seller");
    address inspector = makeAddr("inspector");

    function setUp() public {
        usdc = new MockUSDC();
        PropertyEscrow impl = new PropertyEscrow();
        bytes memory data = abi.encodeWithSelector(PropertyEscrow.initialize.selector, address(usdc), 100, address(this));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), data);
        escrow = PropertyEscrow(address(proxy));

        handler = new Handler(escrow, usdc);

        // Setup caller actor
        targetContract(address(handler));
    }

    function invariant_SolvencyBalance() public view {
        uint256 contractBalance = usdc.balanceOf(address(escrow));

        uint256 calculatedBalance = handler.totalDepositedFunds() - handler.totalWithdrawnFunds();

        assertEq(contractBalance, calculatedBalance, "Solvency invariant broken!");
    }

    function invariant_AgreementCountMatch() public view {
        assertEq(escrow.agreementCount(), handler.activeAgreementsCount(), "Agreement count mismatch!");
    }

    function invariant_ZeroBalanceInCreatedOrCancelledState() public view {
        uint256 length = handler.activeAgreementsCount();
        for (uint256 i = 0; i < length; i++) {
            PropertyEscrow.State state = escrow.getAgreement(i).state;
            uint256 withdrawnAmount = escrow.getAgreement(i).withdrawnAmount;

            if (state == PropertyEscrow.State.Created || state == PropertyEscrow.State.Cancelled) {
                assertEq(withdrawnAmount, 0, "Created/Cancelled agreement has unauthorized withdrawn amount!");
            }
        }
    }

    function invariant_WithdrawnAmountNeverExceedsTotal() public view {
        uint256 length = handler.activeAgreementsCount();
        for (uint256 i = 0; i < length; i++) {
            uint256 withdrawn = escrow.getAgreement(i).withdrawnAmount;
            uint256 total = escrow.getAgreement(i).totalAmount;
            assertLe(withdrawn, total, "Withdrawn amount exceeds total amount!");
        }
    }
    function invariant_MilestonesSumEqualsTotalAmount() public view {
        uint256 length = handler.activeAgreementsCount();
        for (uint256 i = 0; i < length; i++) {
            PropertyEscrow.Agreement memory a = escrow.getAgreement(i);
            uint256 sum = 0;
            for (uint256 j = 0; j < a.milestones.length; j++) {
                sum += a.milestones[j].amount;
            }
            assertEq(sum, a.totalAmount, "Milestone amounts do not sum up to totalAmount!");
        }
    }

}
