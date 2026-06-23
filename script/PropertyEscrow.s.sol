// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {PropertyEscrow} from "../src/PropertyEscrow.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployPropertyEscrow is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address usdcAddress = vm.envAddress("SEPOLIA_USDC_ADDRESS");
        uint256 protocolFeeBps = 100; // 1%

        vm.startBroadcast(deployerPrivateKey);

        PropertyEscrow implementation = new PropertyEscrow();

        console2.log("Implementation deployed at:", address(implementation));

        bytes memory data = abi.encodeWithSelector(
            PropertyEscrow.initialize.selector, usdcAddress, protocolFeeBps, vm.addr(deployerPrivateKey)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);
        console2.log("Proxy deployed at:", address(proxy));

        vm.stopBroadcast();
    }
}
