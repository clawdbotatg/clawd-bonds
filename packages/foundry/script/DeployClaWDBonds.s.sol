// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./DeployHelpers.s.sol";
import "../contracts/ClaWDBonds.sol";
import "../contracts/MockCLAWD.sol";

contract DeployClaWDBonds is ScaffoldETHDeploy {
    function run() external ScaffoldEthDeployerRunner {
        address clawdToken;

        if (block.chainid == 8453) {
            // Base mainnet — use real CLAWD
            clawdToken = 0x9f86dB9fc6f7c9408e8Fda3Ff8ce4e78ac7a6b07;
        } else {
            // Local/testnet — deploy mock and fund treasury
            MockCLAWD mock = new MockCLAWD(deployer);
            clawdToken = address(mock);
        }

        ClaWDBonds bonds = new ClaWDBonds(clawdToken, deployer);

        // On local: fund treasury with 10M CLAWD for testing
        if (block.chainid != 8453) {
            IERC20(clawdToken).approve(address(bonds), 10_000_000e18);
            bonds.fundTreasury(10_000_000e18);
        }
    }
}
