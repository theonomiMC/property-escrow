// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {PropertyEscrow} from "../src/PropertyEscrow.sol";
import {MockUSDC} from "../test/mock/MockUSDC.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployPropertyEscrow is Script {
    MockUSDC public usdc;
    PropertyEscrow public implementation;
    ERC1967Proxy public proxy;
    PropertyEscrow public escrow;

    function run() public {
        address deployer = msg.sender;
        uint256 protocolFee = 100;

        vm.startBroadcast();

        usdc = new MockUSDC();
        implementation = new PropertyEscrow();
        bytes memory data =
            abi.encodeWithSelector(PropertyEscrow.initialize.selector, address(usdc), protocolFee, deployer);
        proxy = new ERC1967Proxy(address(implementation), data);
        escrow = PropertyEscrow(address(proxy));

        vm.stopBroadcast();
    }
}
