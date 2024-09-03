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
import {
    VestedRewardsDistributionJobInit,
    VestedRewardsDistributionJobInitConfig,
    VestedRewardsDistributionJobDeinitConfig,
    VestedRewardsDistributionJobSetDistConfig,
    VestedRewardsDistributionJobRemDistConfig
} from "./VestedRewardsDistributionJobInit.sol";

contract VestedRewardsDistributionJobInitTest is DssTest {
    address constant CHAINLOG = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;

    DssInstance dss;
    address pause;
    ProxyLike pauseProxy;
    SequencerLike sequencer;
    Caller caller;
    VestedRewardsDistributionJobLike job;
    bytes32 constant JOB_KEY = "CRON_VESTED_REWARDS_DIST_JOB";

    function setUp() public {
        vm.createSelectFork("mainnet");

        dss = MCD.loadFromChainlog(CHAINLOG);
        pause = dss.chainlog.getAddress("MCD_PAUSE");
        pauseProxy = ProxyLike(dss.chainlog.getAddress("MCD_PAUSE_PROXY"));
        sequencer = SequencerLike(dss.chainlog.getAddress("CRON_SEQUENCER"));
        caller = new Caller();
        job = VestedRewardsDistributionJobLike(
            caller.deploy(
                VestedRewardsDistributionJobDeployConfig({
                    deployer: address(caller),
                    owner: address(pauseProxy),
                    sequencer: address(sequencer)
                })
            )
        );
    }

    function testInit() public {
        assertFalse(sequencer.hasJob(address(job)), "job already added to sequencer");
        try dss.chainlog.getAddress(JOB_KEY) {
            revert("job already in chainlog");
        } catch {}

        // Simulate a spell casting
        vm.prank(pause);
        pauseProxy.exec(
            address(caller),
            abi.encodeCall(caller.init, (address(job), VestedRewardsDistributionJobInitConfig({jobKey: JOB_KEY})))
        );

        assertTrue(sequencer.hasJob(address(job)), "job not added to sequencer");
        assertEq(dss.chainlog.getAddress(JOB_KEY), address(job), "job not added to chainlog");
    }

    function testDeinit() public {
        // Simulate a spell casting
        vm.prank(pause);
        pauseProxy.exec(
            address(caller),
            abi.encodeCall(caller.init, (address(job), VestedRewardsDistributionJobInitConfig({jobKey: JOB_KEY})))
        );

        assertTrue(sequencer.hasJob(address(job)), "job not in sequencer");
        assertEq(dss.chainlog.getAddress(JOB_KEY), address(job), "job not in chainlog");

        // Simulate a spell casting
        vm.prank(pause);
        pauseProxy.exec(
            address(caller),
            abi.encodeCall(caller.deinit, (address(job), VestedRewardsDistributionJobDeinitConfig({jobKey: JOB_KEY})))
        );

        assertFalse(sequencer.hasJob(address(job)), "job not removed from sequencer");
        try dss.chainlog.getAddress(JOB_KEY) {
            revert("job not removed from chainlog");
        } catch {}
    }

    function testSetDist() public {
        // Simulate a spell casting
        vm.prank(pause);
        pauseProxy.exec(
            address(caller),
            abi.encodeCall(caller.init, (address(job), VestedRewardsDistributionJobInitConfig({jobKey: JOB_KEY})))
        );

        address dist = address(0x1337);
        uint256 interval = 7 days;

        assertFalse(job.has(dist), "dist already in job");
        assertEq(job.intervals(dist), 0, "dist interval already configured in job");

        // Simulate a spell casting
        vm.prank(pause);
        pauseProxy.exec(
            address(caller),
            abi.encodeCall(
                caller.setDist,
                (address(job), VestedRewardsDistributionJobSetDistConfig({dist: dist, interval: interval}))
            )
        );

        assertTrue(job.has(dist), "dist not added to job");
        assertEq(job.intervals(dist), interval, "dist interval not set in job");
    }

    function testRemDist() public {
        // Simulate a spell casting
        vm.prank(pause);
        pauseProxy.exec(
            address(caller),
            abi.encodeCall(caller.init, (address(job), VestedRewardsDistributionJobInitConfig({jobKey: JOB_KEY})))
        );

        address dist = address(0x1337);
        uint256 interval = 7 days;
        // Simulate a spell casting
        vm.prank(pause);
        pauseProxy.exec(
            address(caller),
            abi.encodeCall(
                caller.setDist,
                (address(job), VestedRewardsDistributionJobSetDistConfig({dist: dist, interval: interval}))
            )
        );

        assertTrue(job.has(dist), "dist not in job");
        assertEq(job.intervals(dist), interval, "dist interval not configured in job");

        // Simulate a spell casting
        vm.prank(pause);
        pauseProxy.exec(
            address(caller),
            abi.encodeCall(caller.remDist, (address(job), VestedRewardsDistributionJobRemDistConfig({dist: dist})))
        );

        assertFalse(job.has(dist), "dist not removed from job");
        assertEq(job.intervals(dist), 0, "dist interval not removed from job");
    }
}

interface ProxyLike {
    function exec(address usr, bytes memory fax) external returns (bytes memory out);
}

interface VestedRewardsDistributionJobLike {
    function has(address job) external view returns (bool);
    function intervals(address job) external view returns (uint256);
    function sequencer() external view returns (address);
    function wards(address who) external view returns (uint256);
}

interface SequencerLike {
    function hasJob(address job) external view returns (bool);
}

contract Caller {
    function deploy(VestedRewardsDistributionJobDeployConfig memory cfg) external returns (address) {
        return VestedRewardsDistributionJobDeploy.deploy(cfg);
    }

    function init(address job, VestedRewardsDistributionJobInitConfig memory cfg) external {
        VestedRewardsDistributionJobInit.init(job, cfg);
    }

    function deinit(address job, VestedRewardsDistributionJobDeinitConfig memory cfg) external {
        VestedRewardsDistributionJobInit.deinit(job, cfg);
    }

    function setDist(address job, VestedRewardsDistributionJobSetDistConfig memory cfg) external {
        VestedRewardsDistributionJobInit.setDist(job, cfg);
    }

    function remDist(address job, VestedRewardsDistributionJobRemDistConfig memory cfg) external {
        VestedRewardsDistributionJobInit.remDist(job, cfg);
    }
}
