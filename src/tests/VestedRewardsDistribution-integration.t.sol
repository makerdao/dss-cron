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
import "forge-std/console2.sol";
import "./DssCronBase.t.sol";

import {VestedRewardsDistributionJob} from "../VestedRewardsDistributionJob.sol";

interface VestedRewardsDistributionLike {
    function distribute() external;
    function dssVest() external view returns (address);
    function file(bytes32 what, uint256 data) external;
    function lastDistributedAt() external view returns (uint256);
    function vestId() external view returns (uint256);
}

interface DssVestLike {
    function awards(uint256 _id)
        external
        view
        returns (address usr, uint48 bgn, uint48 clf, uint48 fin, address mgr, uint8 res, uint128 tot, uint128 rxd);
    function create(address _usr, uint256 _tot, uint256 _bgn, uint256 _tau, uint256 _eta, address _mgr)
        external
        returns (uint256 id);
    function restrict(uint256 _id) external;
    function unpaid(uint256 _id) external view returns (uint256 amt);
}

// Note: these tests run only in fork mode on a Tenderly virtual testnet
// RPC URL: https://virtual.mainnet.rpc.tenderly.co/470dbf59-a384-4e77-974c-9430acb2fccb
contract VestedRewardsDistributionJobIntegrationTest is DssCronBaseTest {
    using GodMode for *;
    using stdStorage for StdStorage;

    uint256 RANDOM_INTERVAL = 15;
    VestedRewardsDistributionLike public constant vestedRewardsDist1 =
        VestedRewardsDistributionLike(0x69cA348Bd928A158ADe7aa193C133f315803b06e);
    VestedRewardsDistributionLike public constant vestedRewardsDist2 =
        VestedRewardsDistributionLike(0x53E15917309385Ec8235a5d025A8BeDa2fd0BE3E);

    VestedRewardsDistributionJob public job;

    function setUpSub() internal virtual override {
        job = new VestedRewardsDistributionJob(address(sequencer));
        // add exisitng distros
        job.set(address(vestedRewardsDist1), RANDOM_INTERVAL);
        job.set(address(vestedRewardsDist2), RANDOM_INTERVAL);

        // Give admin access the test contract
        GodMode.setWard(address(vestedRewardsDist1), address(this), 1);
        GodMode.setWard(address(vestedRewardsDist2), address(this), 1);

        GodMode.setWard(vestedRewardsDist1.dssVest(), address(this), 1);
        GodMode.setWard(vestedRewardsDist2.dssVest(), address(this), 1);
    }

    function test_add_rewards_distribution() public {
        address rewardsDist = address(0); //test address
        vm.expectEmit(true, false, false, true);
        emit Set(rewardsDist, RANDOM_INTERVAL);
        job.set(rewardsDist, RANDOM_INTERVAL);
        assertTrue(job.has(rewardsDist));
        assertEq(job.intervals(rewardsDist), RANDOM_INTERVAL);
    }

    function test_add_rewards_distribution_revert_auth() public {
        vm.prank(address(1));
        vm.expectRevert("VestedRewardsDistributionJob/not-authorized");
        job.set(address(0), RANDOM_INTERVAL);
    }

    function test_add_rewards_distribution_overwrite_duplicate() public {
        address rewardsDist = address(0); //test address
        job.set(rewardsDist, RANDOM_INTERVAL);
        job.set(rewardsDist, RANDOM_INTERVAL + 1);

        assertEq(job.intervals(rewardsDist), RANDOM_INTERVAL + 1);
    }

    function test_remove_rewards_distribution() public {
        address rewardsDist = address(0); //test address
        job.set(rewardsDist, RANDOM_INTERVAL);
        vm.expectEmit(true, false, false, false);
        emit Rem(rewardsDist);
        job.rem(rewardsDist);
        assertFalse(job.has(rewardsDist));
        assertEq(job.intervals(rewardsDist), 0);
    }

    function test_remove_rewards_distribution_revert_auth() public {
        vm.prank(address(1));
        vm.expectRevert("VestedRewardsDistributionJob/not-authorized");
        job.rem(address(0));
    }

    function test_remove_rewards_distribution_revert_not_found() public {
        address rewardsDist = address(0); //test address
        vm.expectRevert(abi.encodeWithSelector(VestedRewardsDistributionJob.NotFound.selector, rewardsDist));
        job.rem(rewardsDist);
    }

    function test_modify_distribution_interval() public {
        uint256 newInterval = RANDOM_INTERVAL + 1;
        vm.expectEmit(true, false, false, true);
        emit Set(address(vestedRewardsDist1), newInterval);
        job.set(address(vestedRewardsDist1), newInterval);
        assertEq(job.intervals(address(vestedRewardsDist1)), newInterval);
    }

    function test_modify_distribution_interval_revert_auth() public {
        vm.prank(address(1));
        vm.expectRevert("VestedRewardsDistributionJob/not-authorized");
        job.set(address(vestedRewardsDist1), RANDOM_INTERVAL);
    }

    function test_modify_distribution_interval_revert_invalid_arg() public {
        vm.expectRevert(abi.encodeWithSelector(VestedRewardsDistributionJob.InvalidInterval.selector));
        job.set(address(vestedRewardsDist1), 0);
    }

    function test_work() public {
        uint256 duration = 360 days;
        uint256 total = 100 ether;
        uint256 interval = 7 days;

        job.set(address(vestedRewardsDist1), interval);
        job.rem(address(vestedRewardsDist2));
        DssVestLike vest = DssVestLike(vestedRewardsDist1.dssVest());
        uint256 vestId = _replaceVestingStream(
            address(vestedRewardsDist1), VestParams({bgn: block.timestamp, eta: 0, tau: duration, tot: total})
        );

        // Workable should return false because vest.unpaid(vestId) == 0
        {
            (bool canWork,) = job.workable(NET_A);
            assertFalse(canWork, "initial: workable() should return false");
        }

        // Since this will be the first distribution, the interval cannot be easily enforced
        {
            skip(2 days);
            // Workable now modifies state, so we need this hack to make the test pass.
            uint256 beforeWorkable = vm.snapshot();
            (bool canWork, bytes memory args) = job.workable(NET_A);
            vm.revertTo(beforeWorkable);

            assertTrue(canWork, "1st distribution before interval has passed: workable() should return true");
            (address rewDist) = abi.decode(args, (address));

            vm.expectEmit(true, false, false, true);
            emit Work(NET_A, rewDist, vest.unpaid(vestId));
            job.work(NET_A, args);

            // Checks that there is no vesting amount to be paid
            assertEq(vest.unpaid(vestId), 0, "1st distribution before interval has passed: unexpected unpaid amount");
        }

        // Next not enough time has passed, so the job is not be workable
        {
            skip(3 days);
            assertGt(vest.unpaid(vestId), 0, "before 2nd distribution: unexpected unpaid amount");

            // Workable now modifies state, so we need this hack to make the test pass.
            uint256 beforeWorkable = vm.snapshot();
            (bool canWork, bytes memory args) = job.workable(NET_A);
            vm.revertTo(beforeWorkable);

            assertFalse(canWork, "before 2nd distribution: workable() should return false");
            assertEq(args, bytes("No distribution"));

            vm.expectRevert(
                abi.encodeWithSelector(VestedRewardsDistributionJob.NotDue.selector, address(vestedRewardsDist1))
            );
            job.work(NET_A, abi.encode(address(vestedRewardsDist1)));
        }

        // Now enough time has passed, so the distribution can be made
        {
            skip(4 days);

            // Workable now modifies state, so we need this hack to make the test pass.
            uint256 beforeWorkable = vm.snapshot();
            (bool canWork, bytes memory args) = job.workable(NET_A);
            vm.revertTo(beforeWorkable);

            assertTrue(canWork, "2nd distribution: workable() should return true");
            (address rewDist) = abi.decode(args, (address));

            vm.expectEmit(true, false, false, true);
            emit Work(NET_A, rewDist, vest.unpaid(vestId));
            job.work(NET_A, args);

            // Checks that there is no vesting amount to be paid
            assertEq(vest.unpaid(vestId), 0, "2nd distribution: unexpected unpaid amount");
        }

        // After the vest is expired, the job is no longer executable
        {
            skip(duration);
            // Distribute manually, so there is no remaining
            vestedRewardsDist1.distribute();
            assertEq(vest.unpaid(vestId), 0, "after stream expiration: unpaid amount should be zero");

            // Workable now modifies state, so we need this hack to make the test pass.
            uint256 beforeWorkable = vm.snapshot();
            (bool canWork, bytes memory args) = job.workable(NET_A);
            vm.revertTo(beforeWorkable);

            assertFalse(canWork, "after stream expiration: workable() should return false");
            assertEq(args, bytes("No distribution"));
        }
    }

    function test_work_two_farms() public {
        VestedRewardsDistributionLike[2] memory rewDistributions = [vestedRewardsDist1, vestedRewardsDist2];
        uint256[] memory vestAmounts = new uint256[](2);
        uint256 duration = 360 days;
        uint256 total = 100 ether;

        for (uint256 i = 0; i < 2; i++) {
            VestedRewardsDistributionLike dist = rewDistributions[i];
            DssVestLike vest = DssVestLike(dist.dssVest());

            uint256 vestId = _replaceVestingStream(
                address(dist), VestParams({bgn: block.timestamp - duration / 2, eta: 0, tau: duration, tot: total})
            );

            vestAmounts[i] = vest.unpaid(vestId);
            assertEq(vestAmounts[i], 50 ether, "1st: invalid vest amount");
            assertEq(dist.lastDistributedAt(), 0, "1st: invalid lastDistributedAt");

            // Workable now modifies state, so we need this hack to make the test pass.
            uint256 beforeWorkable = vm.snapshot();
            (, bytes memory args) = job.workable(NET_A);
            vm.revertTo(beforeWorkable);

            (address rewDist) = abi.decode(args, (address));
            vm.expectEmit(true, false, false, true);
            emit Work(NET_A, rewDist, vestAmounts[i]);
            job.work(NET_A, args);

            // check that there is no vesting amount to be paid
            uint256 vestAmount = vest.unpaid(vestId);
            assertEq(vestAmount, 0);
        }
        // now workable should return false
        (bool canWork,) = job.workable(NET_A);
        assertFalse(canWork, "after 1st: workable() returns true");

        // Advances time and try to execute the job once again for both
        uint256 prevTimestamp = block.timestamp;
        job.set(address(vestedRewardsDist1), 7 days);
        job.set(address(vestedRewardsDist2), 7 days);

        // workable should return false because not enough time has elapsed
        skip(2 days);

        for (uint256 i = 0; i < 2; i++) {
            VestedRewardsDistributionLike dist = rewDistributions[i];
            DssVestLike vest = DssVestLike(dist.dssVest());

            vestAmounts[i] = vest.unpaid(dist.vestId());
            assertGe(vestAmounts[i], 0, "after 1st: invalid vest amount");
            assertEq(dist.lastDistributedAt(), prevTimestamp, "2nd: invalid lastDistributedAt");

            // Workable now modifies state, so we need this hack to make the test pass.
            uint256 beforeWorkable = vm.snapshot();
            (canWork,) = job.workable(NET_A);
            vm.revertTo(beforeWorkable);

            assertFalse(canWork, "after 1st: workable() returns true");
        }

        // finally enough time passes, then the job must be workable again
        skip(5 days);

        for (uint256 i = 0; i < 2; i++) {
            VestedRewardsDistributionLike dist = rewDistributions[i];
            DssVestLike vest = DssVestLike(dist.dssVest());

            vestAmounts[i] = vest.unpaid(dist.vestId());
            assertGe(vestAmounts[i], 0, "2nd: invalid vest amount");
            assertEq(dist.lastDistributedAt(), prevTimestamp, "2nd: invalid lastDistributedAt");

            // Workable now modifies state, so we need this hack to make the test pass.
            uint256 beforeWorkable = vm.snapshot();
            (, bytes memory args) = job.workable(NET_A);
            vm.revertTo(beforeWorkable);

            (address rewDist) = abi.decode(args, (address));
            vm.expectEmit(true, false, false, true);
            emit Work(NET_A, rewDist, vestAmounts[i]);
            job.work(NET_A, args);

            // check that there is no vesting amount to be paid
            uint256 vestAmount = vest.unpaid(dist.vestId());
            assertEq(vestAmount, 0);
        }

        // now workable should return false
        (canWork,) = job.workable(NET_A);
        assertFalse(canWork, "after 2nd: workable() returns true");
    }

    function test_cannot_work_if_distribute_reverts() public {
        uint256 duration = 360 days;
        uint256 total = 100 ether;

        job.rem(address(vestedRewardsDist1));
        job.rem(address(vestedRewardsDist2));

        // Ensures the vesting stream is valid
        uint256 vestId = _replaceVestingStream(
            address(vestedRewardsDist1), VestParams({bgn: block.timestamp, eta: 0, tau: duration, tot: total})
        );
        DssVestLike vest = DssVestLike(vestedRewardsDist1.dssVest());

        RevertOnDistributeWrapper dist = new RevertOnDistributeWrapper(address(vestedRewardsDist1));
        job.set(address(dist), RANDOM_INTERVAL);

        // Since this would be the first distribution, the interval cannot be easily enforced,
        // so the job would be workable if distribute did not revert
        {
            skip(2 days);
            assertGt(vest.unpaid(vestId), 0, "unpaid amount should not be zero");

            // Workable now modifies state, so we need this hack to make the test pass.
            uint256 beforeWorkable = vm.snapshot();
            (bool canWork, bytes memory args) = job.workable(NET_A);
            vm.revertTo(beforeWorkable);

            assertFalse(canWork, "workable() should return false");
            assertEq(args, bytes("No distribution"));

            vm.expectRevert("Cannot distribute");
            job.work(NET_A, abi.encode(address(dist)));
        }
    }

    function test_workable_no_distribution() public {
        // call work for both contracts
        bytes memory args = abi.encode(address(vestedRewardsDist1));
        job.work(NET_A, args);
        args = abi.encode(vestedRewardsDist2);
        job.work(NET_A, args);
        bool canWork;
        (canWork, args) = job.workable(NET_A);
        assertFalse(canWork, "workable() returns true");
        assertEq(args, bytes("No distribution"), "Wrong message");
    }

    function test_work_revert_non_master_network() public {
        bytes32 network = "ERROR";
        bytes memory args = abi.encode("0");
        vm.expectRevert(abi.encodeWithSelector(VestedRewardsDistributionJob.NotMaster.selector, network));
        job.work(network, args);
    }

    function test_work_revert_random_distribution() public {
        address rewDist = address(42);
        bytes memory args = abi.encode(rewDist);
        vm.expectRevert(abi.encodeWithSelector(VestedRewardsDistributionJob.NotFound.selector, rewDist));
        job.work(NET_A, args);
    }

    function test_work_revert_garbage_args() public {
        bytes memory args = abi.encode(0x74389);
        (address rewDist) = abi.decode(args, (address));
        vm.expectRevert(abi.encodeWithSelector(VestedRewardsDistributionJob.NotFound.selector, rewDist));
        job.work(NET_A, args);
    }

    function test_work_revert_no_args() public {
        bytes memory emptyArray;
        // empty array, work() should revert
        vm.expectRevert(abi.encodeWithSelector(VestedRewardsDistributionJob.NoArgs.selector));
        job.work(NET_A, emptyArray);
    }

    struct VestParams {
        uint256 bgn;
        uint256 tau;
        uint256 eta;
        uint256 tot;
    }

    function _replaceVestingStream(address dist, VestParams memory p) internal returns (uint256 newVestId) {
        VestedRewardsDistributionLike _dist = VestedRewardsDistributionLike(dist);
        uint256 currentVestId = _dist.vestId();
        DssVestLike vest = DssVestLike(_dist.dssVest());
        (address usr,,,, address mgr, uint8 res,,) = vest.awards(currentVestId);

        newVestId = vest.create(usr, p.tot, p.bgn, p.tau, p.eta, mgr);
        if (res == 1) {
            vest.restrict(newVestId);
        }

        _dist.file("vestId", newVestId);
    }

    // --- Events ---
    event Work(bytes32 indexed network, address indexed rewDist, uint256 amount);
    event Set(address indexed rewdist, uint256 interval);
    event Rem(address indexed rewDist);
}

contract RevertOnDistributeWrapper {
    address internal immutable dist;

    constructor(address _dist) {
        dist = _dist;
    }

    function distribute() public pure {
        revert("Cannot distribute");
    }

    /**
     * @dev Fallback method to forward every other call to the underlying VestedRewardsDistribution contract.
     */
    fallback(bytes calldata _in) external returns (bytes memory) {
        (bool ok, bytes memory out) = dist.call(_in);
        require(ok, string(out));
        return out;
    }
}
