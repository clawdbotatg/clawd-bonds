//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./DeployHelpers.s.sol";
import { DeployClaWDBonds } from "./DeployClaWDBonds.s.sol";

contract DeployScript is ScaffoldETHDeploy {
  function run() external {
    DeployClaWDBonds deployClaWDBonds = new DeployClaWDBonds();
    deployClaWDBonds.run();
  }
}
