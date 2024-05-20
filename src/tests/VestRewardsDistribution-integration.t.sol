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

// Note: these tests run only in fork mode on a Tenderly virtual testnet
// RPC URL: https://virtual.mainnet.rpc.tenderly.co/470dbf59-a384-4e77-974c-9430acb2fccb
contract VestRewardsDistributionJobIntegrationTest is DssCronBaseTest {
    using GodMode for *;

    uint256 RANDOM_INTERVAL = 15;
    address public constant vestedRewardsDist1 = 0x69cA348Bd928A158ADe7aa193C133f315803b06e;
    address public constant vestedRewardsDist2 = 0x53E15917309385Ec8235a5d025A8BeDa2fd0BE3E;

    VestRewardsDistributionJob public vestRewardsDistributionJob;

    // --- Events ---
    event Work(bytes32 indexed network, address indexed rewDist, uint distAmounts);
    event AddRewardDistribution(address indexed rewdist, uint256 interval);
    event RemoveRewardDistribution(address indexed rewDist);
    event ModifyDistributionInterval(address indexed rewDist, uint256 interval);

    function setUpSub() internal virtual override {
        vestRewardsDistributionJob =
            new VestRewardsDistributionJob(address(sequencer));
        // add exisitng distros
        vestRewardsDistributionJob.addRewardDistribution(vestedRewardsDist1, RANDOM_INTERVAL);
        vestRewardsDistributionJob.addRewardDistribution(vestedRewardsDist2, RANDOM_INTERVAL);
    }

    function test_add_reward_distribution() public {
        address rewardsDist = address(0); //test address
        vm.expectEmit(true, false, false, true);
        emit AddRewardDistribution(rewardsDist, RANDOM_INTERVAL);
        vestRewardsDistributionJob.addRewardDistribution(rewardsDist, RANDOM_INTERVAL);
        assertTrue(vestRewardsDistributionJob.rewardDistributionActive(rewardsDist));
        assertEq(vestRewardsDistributionJob.distributionIntervals(rewardsDist), RANDOM_INTERVAL);
    }

    function test_add_reward_distribution_revert_auth() public {
        vm.prank(address(1));
        vm.expectRevert("VestRewards/not-authorized");
        vestRewardsDistributionJob.addRewardDistribution(address(0), RANDOM_INTERVAL);
    }

    function test_add_reward_distribution_revert_duplicate() public {
        address rewardsDist = address(0); //test address
        vestRewardsDistributionJob.addRewardDistribution(rewardsDist, RANDOM_INTERVAL);
        vm.expectRevert(abi.encodeWithSelector(VestRewardsDistributionJob.RewardDistributionExists.selector, rewardsDist));
        vestRewardsDistributionJob.addRewardDistribution(rewardsDist, RANDOM_INTERVAL);
    }

    function test_remove_reward_distribution() public {
        address rewardsDist = address(0); //test address
        vestRewardsDistributionJob.addRewardDistribution(rewardsDist, RANDOM_INTERVAL);
        vm.expectEmit(true, false, false, false);
        emit RemoveRewardDistribution(rewardsDist);
        vestRewardsDistributionJob.removeRewardDistribution(rewardsDist);
        assertFalse(vestRewardsDistributionJob.rewardDistributionActive(rewardsDist));
        assertEq(vestRewardsDistributionJob.distributionIntervals(rewardsDist), 0);
    }

    function test_remove_reward_distribution_revert_auth() public {
        vm.prank(address(1));
        vm.expectRevert("VestRewards/not-authorized");
        vestRewardsDistributionJob.removeRewardDistribution(address(0));
    }

    function test_remove_reward_distribution_revert_not_found() public {
        address rewardsDist = address(0); //test address
        vm.expectRevert(abi.encodeWithSelector(VestRewardsDistributionJob.RewardDistributionDoesNotExist.selector, rewardsDist));
        vestRewardsDistributionJob.removeRewardDistribution(rewardsDist);
    }

    function test_modify_distribution_interval() public {
        uint256 newInterval = RANDOM_INTERVAL + 1;
        vm.expectEmit(true, false, false, true);
        emit ModifyDistributionInterval(vestedRewardsDist1, newInterval);
        vestRewardsDistributionJob.modifyDistributionInterval(vestedRewardsDist1, newInterval);
        assertEq(vestRewardsDistributionJob.distributionIntervals(vestedRewardsDist1), newInterval);
    }

    function test_modify_distribution_interval_revert_auth() public {
        vm.prank(address(1));
        vm.expectRevert("VestRewards/not-authorized");
        vestRewardsDistributionJob.modifyDistributionInterval(vestedRewardsDist1, RANDOM_INTERVAL);
    }

    function test_modify_distribution_interval_revert_not_found() public {
        address rewardsDist = address(0); //test address
        vm.expectRevert(abi.encodeWithSelector(VestRewardsDistributionJob.RewardDistributionDoesNotExist.selector, rewardsDist));
        vestRewardsDistributionJob.modifyDistributionInterval(rewardsDist, RANDOM_INTERVAL);
    }

    function test_workable_two_farms() public {
        (bool canWork, bytes memory args) = vestRewardsDistributionJob.workable(NET_A);
        (address rewDist) = abi.decode(args, (address));
        assertTrue(canWork, "workable() returns false");
        assertEq(rewDist, vestedRewardsDist1);
    }

    function test_workable_no_farms() public {
        // remove distributions
        vestRewardsDistributionJob.removeRewardDistribution(vestedRewardsDist1);
        vestRewardsDistributionJob.removeRewardDistribution(vestedRewardsDist2);
        (bool canWork, bytes memory args) = vestRewardsDistributionJob.workable(NET_A);
        assertFalse(canWork, "workable() returns true");
        assertEq(args, bytes("No farms"), "Wrong message");
    }

    function test_workable_no_distribution() public {
        // call work for both contracts
        bytes memory args = abi.encode(vestedRewardsDist1);
        vestRewardsDistributionJob.work(NET_A, args);
        args = abi.encode(vestedRewardsDist2);
        vestRewardsDistributionJob.work(NET_A, args);
        bool canWork;
        (canWork, args) = vestRewardsDistributionJob.workable(NET_A);
        assertFalse(canWork, "workable() returns true");
        assertEq(args, bytes("No distribution"), "Wrong message");
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
        // call workable() and work() twice
        for (uint256 i = 0; i < 2; i++) {
            (, bytes memory args) = vestRewardsDistributionJob.workable(NET_A);
            (address rewDist) = abi.decode(args, (address));
            vm.expectEmit(true, false, false, true);
            emit Work(NET_A, rewDist, vestAmounts[i]);
            vestRewardsDistributionJob.work(NET_A, args);
            // check that there is no vesting amount to be paid
            address dist = rewDistributions[i];
            address dssVest = VestedRewardsDistributionLike(dist).dssVest();
            uint256 vestId = VestedRewardsDistributionLike(dist).vestId();
            uint256 vestAmount = DssVestLike(dssVest).unpaid(vestId);
            assertEq(vestAmount, 0);
        }
        // now workable should return false
        (bool canWork, ) = vestRewardsDistributionJob.workable(NET_A);
        assertFalse(canWork, "workable() returns true");
    }

    function test_work_revert_non_master_network() public {
        bytes32 network = "ERROR";
        bytes memory args = abi.encode("0");
        vm.expectRevert(abi.encodeWithSelector(VestRewardsDistributionJob.NotMaster.selector, network));
        vestRewardsDistributionJob.work(network, args);
    }

    function test_work_revert_random_distribution() public {
        address rewDist = address(42);
        bytes memory args = abi.encode(rewDist);
        vm.expectRevert(abi.encodeWithSelector(VestRewardsDistributionJob.RewardDistributionDoesNotExist.selector, rewDist));
        vestRewardsDistributionJob.work(NET_A, args);
    }

    function test_work_revert_garbage_args() public {
        bytes memory args = abi.encode(0x74389);
        (address rewDist) = abi.decode(args, (address));
        vm.expectRevert(abi.encodeWithSelector(VestRewardsDistributionJob.RewardDistributionDoesNotExist.selector, rewDist));
        vestRewardsDistributionJob.work(NET_A, args);
    }

    function test_work_revert_no_args() public {
        bytes memory emptyArray;
        // empty array, work() should revert
        vm.expectRevert(abi.encodeWithSelector(VestRewardsDistributionJob.NoArgs.selector));
        vestRewardsDistributionJob.work(NET_A, emptyArray);
    }
}
