// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2021 Dai Foundation
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

import "forge-std/Test.sol";
import "./DssCronBase.t.sol";

import {VestRewardsDistributionJob} from "../VestRewardsDistributionJob.sol";

contract VestRewardsDistributionJobIntegrationTest is DssCronBaseTest {
    using GodMode for *;

    uint256 constant MILLION_WAD = MILLION * WAD;

    VestRewardsDistributionJob public vestRewardsDistributionJob;

    // --- Events ---
    event Work(bytes32 indexed network);
    event AddRewardDistribution(address indexed rewdist);
    event RemoveRewardDistribution(address indexed rewDist);

    function setUpSub() internal virtual override {
        vestRewardsDistributionJob =
            new VestRewardsDistributionJob(address(sequencer));
    }

    function test_add_reward_distribution() public {
        address rewardsDist = address(0); //test address
        vm.expectEmit(true, false, false, false);
        emit AddRewardDistribution(rewardsDist);
        vestRewardsDistributionJob.addRewardDistribution(rewardsDist);
        assertTrue(vestRewardsDistributionJob.rewardDistributionActive(rewardsDist));
    }

    function test_add_reward_distribution_fail_auth() public {
        vm.prank(address(1));
        vm.expectRevert("VestRewards/not-authorized");
        vestRewardsDistributionJob.addRewardDistribution(address(0));
    }

    function test_add_reward_distribution_fail_duplicate() public {
        address rewardsDist = address(0); //test address
        vestRewardsDistributionJob.addRewardDistribution(rewardsDist);
        vm.expectRevert(abi.encodeWithSelector(VestRewardsDistributionJob.RewardDistributionExists.selector, rewardsDist));
        vestRewardsDistributionJob.addRewardDistribution(rewardsDist);
    }

    function test_remove_reward_distribution() public {
        address rewardsDist = address(0); //test address
        vestRewardsDistributionJob.addRewardDistribution(rewardsDist);
        vm.expectEmit(true, false, false, false);
        emit RemoveRewardDistribution(rewardsDist);
        vestRewardsDistributionJob.removeRewardDistribution(rewardsDist);
        assertFalse(vestRewardsDistributionJob.rewardDistributionActive(rewardsDist));
    }

    function test_remove_reward_distribution_fail_auth() public {
        vm.prank(address(1));
        vm.expectRevert("VestRewards/not-authorized");
        vestRewardsDistributionJob.removeRewardDistribution(address(0));
    }

    function test_remove_reward_distribution_fail_not_found() public {
        address rewardsDist = address(0); //test address
        vm.expectRevert(abi.encodeWithSelector(VestRewardsDistributionJob.RewardDistributionDoesNotExist.selector, rewardsDist));
        vestRewardsDistributionJob.removeRewardDistribution(rewardsDist);
    }

    /**
     *  Other Revert Test Cases **
     */

    function test_non_master_network() public {
        bytes32 network = "ERROR";
        bytes memory args = abi.encode("0");
        vm.expectRevert(abi.encodeWithSelector(VestRewardsDistributionJob.NotMaster.selector, network));
        vestRewardsDistributionJob.work(network, args);
    }

    function test_no_work() public {
        (bool canWork, bytes memory args) = vestRewardsDistributionJob.workable(NET_A);
        assertTrue(canWork == false, "workable() returns true");
        assertEq(args, bytes("No farms"), "Wrong message");
    }

}
