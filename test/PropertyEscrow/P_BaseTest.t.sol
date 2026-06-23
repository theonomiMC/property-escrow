// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MockUSDC} from "../../test/mock/MockUSDC.sol";
import {PropertyEscrow} from "../../src/PropertyEscrow.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

abstract contract PropertyEscrowBaseTest is Test {
    MockUSDC public usdc;
    PropertyEscrow public escrow;

    address buyer = makeAddr("buyer");
    address seller = makeAddr("seller");
    address inspector = makeAddr("inspector");
    address unauthorizedUser = makeAddr("Unauthorized User");

    uint256 defaultFee = 100e6;
    uint256 defaultDeadline = block.timestamp + 10 days;
    uint256 defaultAgreementId;

    function setUp() public virtual {
        usdc = new MockUSDC();
        PropertyEscrow impl = new PropertyEscrow();
        bytes memory data = abi.encodeWithSelector(
            PropertyEscrow.initialize.selector,
            address(usdc),
            100, // protocol fee
            address(this) // deployer
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), data);
        escrow = PropertyEscrow(address(proxy));

        usdc.mint(buyer, 10000e6);
        vm.prank(buyer);
        usdc.approve(address(escrow), 10000e6);
    }

    // HELPERS
    // 1. Create milestones array
    function _createMilestones(uint256 qty, uint256 amountPerQty)
        internal
        pure
        returns (PropertyEscrow.Milestone[] memory)
    {
        PropertyEscrow.Milestone[] memory m = new PropertyEscrow.Milestone[](qty);

        for (uint256 i = 0; i < qty; i++) {
            m[i].amount = uint128(amountPerQty);
            m[i].descriptionHash = keccak256(abi.encode(i));
        }
        return m;
    }

    function _createAgreementOnly(
        address _buyer,
        address _seller,
        address _inspector,
        uint32 _deadline,
        uint256 _fee,
        uint256 milestoneCount,
        uint256 amountPerMilestone
    ) internal returns (uint256) {
        PropertyEscrow.Milestone[] memory m = _createMilestones(milestoneCount, amountPerMilestone);

        vm.prank(_seller);
        uint256 id = escrow.createAgreement(_buyer, _seller, _inspector, _deadline, _fee, m);

        return id;
    }

    // 2. Create + fund in one call
    function _createAndFundAgreement(
        address _buyer,
        address _seller,
        address _inspector,
        uint32 _deadline,
        uint256 _fee,
        uint256 milestoneCount,
        uint256 amountPerMilestone
    ) internal returns (uint256) {
        PropertyEscrow.Milestone[] memory m = _createMilestones(milestoneCount, amountPerMilestone);

        vm.prank(_seller);
        uint256 id = escrow.createAgreement(_buyer, _seller, _inspector, _deadline, _fee, m);

        vm.prank(_buyer);
        escrow.depositFunds(id);
        return id;
    }

    // 3. Approve
    function _approveFrom(address approveFrom, uint256 agreementId, uint256 milestoneId) internal {
        vm.prank(approveFrom);
        escrow.approveMilestone(agreementId, milestoneId);
    }

    // get agreement state
    function _getState(uint256 agreementId) internal view returns (PropertyEscrow.State) {
        (PropertyEscrow.State state,,,,,,,,,,,) = escrow.agreements(agreementId);
        return state;
    }

    // get agreement total amount
    function _getAgrTotalAmount(uint256 agreementId) internal view returns (uint256) {
        (,,,,,,,,, uint256 totalAmount,,) = escrow.agreements(agreementId);

        return totalAmount;
    }

    modifier givenFundedAgreement() {
        defaultAgreementId =
            _createAndFundAgreement(buyer, seller, inspector, uint32(defaultDeadline), defaultFee, 2, 500e6);
        _;
    }

    modifier givenDisputedAgreement() {
        defaultAgreementId =
            _createAndFundAgreement(buyer, seller, inspector, uint32(defaultDeadline), defaultFee, 2, 500e6);
        vm.prank(buyer);
        escrow.openDispute(defaultAgreementId);
        _;
    }
}
