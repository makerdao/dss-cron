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

interface VestedRewardsDistributionLike {
    function dssVest() external view returns (address);
    function vestId() external view returns (uint256);
}

interface DssVestLike {
    function unpaid(uint256 _id) external view returns (uint256 amt);
}

contract VestRewardsDistributionJobIntegrationTest is DssCronBaseTest {
    using GodMode for *;

    address public constant vestedRewardsDist1 = 0x69cA348Bd928A158ADe7aa193C133f315803b06e;
    address public constant vestedRewardsDist2 = 0x53E15917309385Ec8235a5d025A8BeDa2fd0BE3E;

    VestRewardsDistributionJob public vestRewardsDistributionJob;

    // --- Events ---
    event Work(bytes32 indexed network, address[] rewDist, uint[] distAmounts);
    event AddRewardDistribution(address indexed rewdist);
    event RemoveRewardDistribution(address indexed rewDist);

    function setUpSub() internal virtual override {
        vestRewardsDistributionJob =
            new VestRewardsDistributionJob(address(sequencer));
        // add exisitng distros
        vestRewardsDistributionJob.addRewardDistribution(vestedRewardsDist1);
        vestRewardsDistributionJob.addRewardDistribution(vestedRewardsDist2);
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

    function test_workable_no_farms() public {
        // remove distributions
        vestRewardsDistributionJob.removeRewardDistribution(vestedRewardsDist1);
        vestRewardsDistributionJob.removeRewardDistribution(vestedRewardsDist2);
        (bool canWork, bytes memory args) = vestRewardsDistributionJob.workable(NET_A);
        assertTrue(canWork == false, "workable() returns true");
        assertEq(args, bytes("No farms"), "Wrong message");
    }

    function test_workable_two_farms() public {
        (bool canWork, bytes memory args) = vestRewardsDistributionJob.workable(NET_A);
        (address[] memory rewDist) = abi.decode(args, (address[]));
        assertTrue(canWork, "workable() returns false");
        assertEq(rewDist.length, 2);
    }

    function test_work_two_farms() public {
        address[2] memory rewDistributions = [vestedRewardsDist1, vestedRewardsDist1];
        uint256[] memory vestAmounts = new uint256[](2);
        for (uint256 i = 0; i < 2; i++) {
            address dist = rewDistributions[i];
            address dssVest = VestedRewardsDistributionLike(dist).dssVest();
            uint256 vestId = VestedRewardsDistributionLike(dist).vestId();
            vestAmounts[i] = DssVestLike(dssVest).unpaid(vestId);
            // give auth access: VestedRewardsDistribution to DssVest
            GodMode.setWard(dssVest, dist, 1);
        }
        (, bytes memory args) = vestRewardsDistributionJob.workable(NET_A);
        (address[] memory rewDist) = abi.decode(args, (address[]));
        assertEq(rewDist.length, 2);
        vm.expectEmit(true, false, false, true);
        emit Work(NET_A, rewDist, vestAmounts);
        vestRewardsDistributionJob.work(NET_A, args);
        // check that there is no vesting amount to be paid
        for (uint256 i = 0; i < 2; i++) {
            address dist = rewDistributions[i];
            address dssVest = VestedRewardsDistributionLike(dist).dssVest();
            uint256 vestId = VestedRewardsDistributionLike(dist).vestId();
            uint256 vestAmount = DssVestLike(dssVest).unpaid(vestId);
            assertEq(vestAmount, 0);
        }
    }

    function test_work_one_farm() public {
        address[] memory rewDistributions = new address[](1);
        rewDistributions[0] = vestedRewardsDist1;
        bytes memory args = abi.encode(rewDistributions);
        vestRewardsDistributionJob.work(NET_A, args);
        // workable() should now return only one rewardDistribution
        (, args) = vestRewardsDistributionJob.workable(NET_A);
        (address[] memory rewDist) = abi.decode(args, (address[]));
        assertEq(rewDist.length, 1);
        assertEq(rewDist[0], vestedRewardsDist2);
        // work should now distribute rewards for the remaining farm
        address dssVest = VestedRewardsDistributionLike(vestedRewardsDist2).dssVest();
        uint256 vestId = VestedRewardsDistributionLike(vestedRewardsDist2).vestId();
        uint256[] memory vestAmounts = new uint256[](1);
        vestAmounts[0] = DssVestLike(dssVest).unpaid(vestId);
        vm.expectEmit(true, false, false, true);
        emit Work(NET_A, rewDist, vestAmounts);
        vestRewardsDistributionJob.work(NET_A, args);
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
    function test_work_random_distribution() public {
        address[] memory rewDistributions = new address[](1);
        rewDistributions[0] = address(42);
        bytes memory args = abi.encode(rewDistributions);
        vm.expectRevert(abi.encodeWithSelector(VestRewardsDistributionJob.RewardDistributionDoesNotExist.selector, rewDistributions[0]));
        vestRewardsDistributionJob.work(NET_A, args);
    }

    function test_work_no_distribution() public {
        address[] memory vestingFarms;
        // empty array, work() should revert
        vm.expectRevert(abi.encodeWithSelector(VestRewardsDistributionJob.NothingToDistribute.selector));
        vestRewardsDistributionJob.work(NET_A, abi.encode(vestingFarms));
    }

}
