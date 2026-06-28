// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {PropertyEscrow} from "../src/PropertyEscrow.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract UpgradePropertyEscrow is Script {
    address public constant PROXY_ADDRESS = 0xfe6aF1412F08AC469f79B8BF6FB471FF02c5f3d3;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        PropertyEscrow newImplementation = new PropertyEscrow();
        console2.log("New Implementation deployed at:", address(newImplementation));

        PropertyEscrow proxy = PropertyEscrow(PROXY_ADDRESS);

        UUPSUpgradeable(address(proxy)).upgradeToAndCall(address(newImplementation), "");

        console2.log("Proxy successfully upgraded at:", address(proxy));

        vm.stopBroadcast();
    }
}
