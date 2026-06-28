// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {DeployPropertyEscrow} from "../../script/PropertyEscrow.s.sol";
import {PropertyEscrow} from "../../src/PropertyEscrow.sol";

contract PropertyEscrowScriptTest is Test {
    DeployPropertyEscrow public deployerScript;

    function setUp() public {
        deployerScript = new DeployPropertyEscrow();

        vm.setEnv("PRIVATE_KEY", "0xabc123abc123abc123abc123abc123abc123abc123abc123abc123abc123abc1");

        vm.setEnv("SEPOLIA_USDC_ADDRESS", "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238");

    }

    function test_ScriptDeploymentFlow() public {
        deployerScript.run();
    }
}
