// SPDX-FileCopyrightText: © 2023 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.
pragma solidity 0.8.13;

import "dss-test/DssTest.sol";
import {
    VestedRewardsDistributionJobDeploy,
    VestedRewardsDistributionJobDeployConfig
} from "./VestedRewardsDistributionJobDeploy.sol";

contract VestedRewardsDistributionJobDeployTest is DssTest {
    address constant CHAINLOG = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;

    DssInstance dss;
    address pauseProxy;
    address sequencer;
    DeployCaller caller;
    VestedRewardsDistributionJobDeployConfig cfg;

    function setUp() public {
        vm.createSelectFork("mainnet");

        dss = MCD.loadFromChainlog(CHAINLOG);
        pauseProxy = dss.chainlog.getAddress("MCD_PAUSE_PROXY");
        sequencer = dss.chainlog.getAddress("CRON_SEQUENCER");
        caller = new DeployCaller();
        cfg =
            VestedRewardsDistributionJobDeployConfig({deployer: address(caller), owner: pauseProxy, sequencer: sequencer});
    }

    function testDeploy() public {
        VestedRewardsDistributionJobLike job = VestedRewardsDistributionJobLike(caller.deploy(cfg));

        assertEq(job.sequencer(), sequencer, "invalid sequencer");
        assertEq(job.wards(pauseProxy), 1, "pauseProxy not ward");
        assertEq(job.wards(address(caller)), 0, "deployer still ward");
    }
}

interface VestedRewardsDistributionJobLike {
    function sequencer() external view returns (address);
    function wards(address who) external view returns (uint256);
}

contract DeployCaller {
    function deploy(VestedRewardsDistributionJobDeployConfig memory cfg) external returns (address) {
        return VestedRewardsDistributionJobDeploy.deploy(cfg);
    }
}
