// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PropertyEscrow} from "../../src/PropertyEscrow.sol";
import {MockUSDC} from "../mock/MockUSDC.sol";

contract Handler is Test {
    PropertyEscrow public escrow;
    MockUSDC public usdc;

    uint256 public totalDepositedFunds;
    uint256 public totalWithdrawnFunds;
    uint256 public activeAgreementsCount;

    address public buyer;
    address public seller;
    address public inspector;

    mapping(uint256 => bool) public agreementExists;
    mapping(uint256 => bool) public agreementFunded;
    uint256[] public agreementIds;

    constructor(PropertyEscrow _escrow, MockUSDC _usdc) {
        escrow = _escrow;
        usdc = _usdc;
        buyer = makeAddr("buyer");
        seller = makeAddr("seller");
        inspector = makeAddr("inspector");

        usdc.mint(buyer, type(uint256).max);
        vm.prank(buyer);
        usdc.approve(address(escrow), type(uint256).max);
    }

    function createAgreement_Handler(uint32 deadline, uint256 fee) public {
        deadline = uint32(bound(deadline, block.timestamp + 1 days, block.timestamp + 364 days));

        fee = bound(fee, 1e6, 1000e6);

        PropertyEscrow.Milestone[] memory m = new PropertyEscrow.Milestone[](2);
        m[0] = PropertyEscrow.Milestone({
            amount: 500e6,
            completed: false,
            inspectorApproved: false,
            buyerApproved: false,
            sellerApproved: false,
            descriptionHash: keccak256("build html page")
        });
        m[1] = PropertyEscrow.Milestone({
            amount: 300e6,
            completed: false,
            inspectorApproved: false,
            buyerApproved: false,
            sellerApproved: false,
            descriptionHash: keccak256("styling")
        });

        vm.prank(buyer);
        try escrow.createAgreement(buyer, seller, inspector, deadline, fee, m) returns (uint256 id) {
            agreementIds.push(id);
            agreementExists[id] = true;
            agreementFunded[id] = false;
            activeAgreementsCount++;
        } catch {}
    }

    function depositFunds_Handler(uint256 idIndex) public {
        if (agreementIds.length == 0) return;
        uint256 id = agreementIds[bound(idIndex, 0, agreementIds.length - 1)];

        if (agreementFunded[id]) return;

        uint256 balanceBefore = usdc.balanceOf(address(escrow));

        vm.prank(buyer);
        try escrow.depositFunds(id) {
            agreementFunded[id] = true;
            uint256 balanceAfter = usdc.balanceOf(address(escrow));
            totalDepositedFunds += (balanceAfter - balanceBefore);
        } catch {}
    }

    function approveMilestone_Handler(uint256 idIndex, uint256 milestoneId) public {
        if (agreementIds.length == 0) return;
        uint256 id = agreementIds[bound(idIndex, 0, agreementIds.length - 1)];

        if (!agreementFunded[id]) return;

        milestoneId = bound(milestoneId, 0, 1);

        vm.prank(buyer);
        try escrow.approveMilestone(id, milestoneId) {} catch {}
    }

    function releaseFunds_Handler(uint256 idIndex, uint256 actorSeed, uint256 milestoneId) public {
        if (agreementIds.length == 0) return;
        uint256 id = agreementIds[bound(idIndex, 0, agreementIds.length - 1)];

        if (!agreementFunded[id]) return;

        milestoneId = bound(milestoneId, 0, 1);

        address actor = (actorSeed % 2 == 0) ? buyer : seller;

        uint256 buyerBalanceBefore = usdc.balanceOf(buyer);
        uint256 sellerBalanceBefore = usdc.balanceOf(seller);
        uint256 inspectorBalanceBefore = usdc.balanceOf(inspector);

        vm.prank(actor);
        try escrow.releaseFunds(id, milestoneId) {
            totalWithdrawnFunds += (usdc.balanceOf(buyer) - buyerBalanceBefore);
            totalWithdrawnFunds += (usdc.balanceOf(seller) - sellerBalanceBefore);
            totalWithdrawnFunds += (usdc.balanceOf(inspector) - inspectorBalanceBefore);
        } catch {}
    }

    function refundFunds_handler(uint256 idIndex, uint256 warpTime) public {
        if (agreementIds.length == 0) return;
        uint256 id = agreementIds[bound(idIndex, 0, agreementIds.length - 1)];

        warpTime = bound(warpTime, 1 days, 365 days);
        vm.warp(block.timestamp + warpTime);

        uint256 buyerBalanceBefore = usdc.balanceOf(buyer);
        uint256 sellerBalanceBefore = usdc.balanceOf(seller);
        uint256 inspectorBalanceBefore = usdc.balanceOf(inspector);

        if (!agreementFunded[id]) return;

        vm.prank(buyer);
        try escrow.refundFunds(id) {
            totalWithdrawnFunds += (usdc.balanceOf(buyer) - buyerBalanceBefore);
            totalWithdrawnFunds += (usdc.balanceOf(seller) - sellerBalanceBefore);
            totalWithdrawnFunds += (usdc.balanceOf(inspector) - inspectorBalanceBefore);
        } catch {}
    }

    function openDispute_Handler(uint256 idIndex, uint256 actorSeed) public {
        if (agreementIds.length == 0) return;
        uint256 id = agreementIds[bound(idIndex, 0, agreementIds.length - 1)];

        address actor = (actorSeed % 2 == 0) ? buyer : seller;

        vm.prank(actor);
        try escrow.openDispute(id) {} catch {}
    }

    function resolveDispute_Handler(uint256 idIndex, uint256 buyerShare) public {
        if (agreementIds.length == 0) return;
        uint256 id = agreementIds[bound(idIndex, 0, agreementIds.length - 1)];

        uint256 totalAmount = 800e6;
        buyerShare = bound(buyerShare, 0, totalAmount);
        uint256 sellerShare = totalAmount - buyerShare;

        uint256 buyerBalanceBefore = usdc.balanceOf(buyer);
        uint256 sellerBalanceBefore = usdc.balanceOf(seller);
        uint256 inspectorBalanceBefore = usdc.balanceOf(inspector);

        vm.prank(inspector);
        try escrow.resolveDispute(id, buyerShare, sellerShare) {
            totalWithdrawnFunds += (usdc.balanceOf(buyer) - buyerBalanceBefore);
            totalWithdrawnFunds += (usdc.balanceOf(seller) - sellerBalanceBefore);
            totalWithdrawnFunds += (usdc.balanceOf(inspector) - inspectorBalanceBefore);
        } catch {}
    }
}
