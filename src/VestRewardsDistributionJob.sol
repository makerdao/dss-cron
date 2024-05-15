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

import {IJob} from "./interfaces/IJob.sol";
import "./utils/EnumerableSet.sol";

interface SequencerLike {
    function isMaster(bytes32 network) external view returns (bool);
}

interface DssVestWithGemLike {
    function unpaid(uint256 _id) external view returns (uint256);
}

interface VestedRewardsDistributionLike {
    function distribute() external returns (uint256 amount);
    function dssVest() external view returns (DssVestWithGemLike);
    function lastDistributedAt() external view returns (uint256);
    function vestId() external view returns (uint256);
}

/// @title Call distribute() when possible
contract VestRewardsDistributionJob is IJob {

    using EnumerableSet for EnumerableSet.AddressSet;

    // --- Auth ---
    mapping (address => uint256) public wards;

    function rely(address usr) external auth {
        wards[usr] = 1;

        emit Rely(usr);
    }
    function deny(address usr) external auth {
        wards[usr] = 0;

        emit Deny(usr);
    }
    modifier auth {
        require(wards[msg.sender] == 1, "VestRewards/not-authorized");
        _;
    }

    uint256 constant timeMagicNumber = 5 * 52 weeks; // 5 years

    uint256 public immutable minimumDelay;
    SequencerLike public immutable sequencer;


    EnumerableSet.AddressSet private distributions;


    mapping(address => uint256) public distributionDelays;

    // --- Errors ---
    error CannotDistributeYet(address rewDist);
    error LessThanMinimumDelay(uint256 delay);
    error NotMaster(bytes32 network);
    error RewardDistributionExists(address rewDist);
    error RewardDistributionDoesNotExist(address rewDist);

    // --- Events ---
    event Work(bytes32 indexed network, address rewDist, uint distAmounts);
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event AddRewardDistribution(address indexed rewDist, uint256 delay);
    event RemoveRewardDistribution(address indexed rewDist);
    event ModifiedDistributionDelay(address indexed rewDist, uint256 delay);

    constructor(
        address _sequencer,
        uint256 _minimumDelay
    ) {
        sequencer = SequencerLike(_sequencer);
        minimumDelay = _minimumDelay;
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Reward Distribution Admin ---
    function addRewardDistribution(address rewDist, uint256 delay) external auth {
        if (!distributions.add(rewDist)) revert RewardDistributionExists(rewDist);
        if (delay < minimumDelay) revert LessThanMinimumDelay(delay);
        distributionDelays[rewDist] = delay;
        emit AddRewardDistribution(rewDist, delay);
    }

    function removeRewardDistribution(address rewDist) external auth {
        if (!distributions.remove(rewDist)) revert RewardDistributionDoesNotExist(rewDist);
        delete distributionDelays[rewDist];
        emit RemoveRewardDistribution(rewDist);
    }

    function modifyDistributionDelay(address rewDist, uint256 delay) external auth {
        if (!distributions.contains(rewDist)) revert RewardDistributionDoesNotExist(rewDist);
        if (delay < minimumDelay) revert LessThanMinimumDelay(delay);
        distributionDelays[rewDist] = delay;
        emit ModifiedDistributionDelay(rewDist, delay);
    }

    function work(bytes32 network, bytes calldata args) public {
        if (!sequencer.isMaster(network)) revert NotMaster(network);

        (address rewDist) = abi.decode(args, (address));

        // prevent keeper from calling random contracts having distribute()
        if (!distributions.contains(rewDist)) revert RewardDistributionDoesNotExist(rewDist);
        // ensure that the right delay has elapsed
        if (canDistributeAfter(rewDist) >= block.timestamp) revert CannotDistributeYet(rewDist);
        // we omit checking the unpaid amount because if it is 0 it will revert during distribute()
        uint256 distAmount = VestedRewardsDistributionLike(rewDist).distribute();
        emit Work(network, rewDist, distAmount);
    }

    function workable(bytes32 network) external view override returns (bool, bytes memory) {
        if (!sequencer.isMaster(network)) return (false, bytes("Network is not master"));

        uint256 distributionsLen = distributions.length();
        if (distributionsLen > 0) {
            address distributable;
            // this is used to find the distribute() than could have been called the earliest
            // we use a hack that ensures the right functionality while avoiding an extra check for 0 value
            uint256 earliestDistCall = block.timestamp + timeMagicNumber;
            for (uint256 i = 0; i < distributionsLen; i++) {
                address rewDist = distributions.at(i);
                uint256 nextDistCall = canDistributeAfter(rewDist);
                // timestamp should be strictly greater than nextDistCall
                if (nextDistCall < block.timestamp) {
                    uint256 vestId = VestedRewardsDistributionLike(rewDist).vestId();
                    DssVestWithGemLike dssVest = VestedRewardsDistributionLike(rewDist).dssVest();
                    uint256 amount = dssVest.unpaid(vestId);
                    if (amount > 0){
                        if (nextDistCall < earliestDistCall)
                            distributable = rewDist;
                    }
                }
            }
            return (true, abi.encode(distributable));

        }
        else {
            return (false, bytes("No farms"));
        }
    }

    function rewardDistributionActive(address rewDist) public view returns (bool) {
        return distributions.contains(rewDist);
    }

    function canDistributeAfter(address rewDist) internal view returns (uint256) {
        // get the last time distribute() was called
        uint256 distTimestamp = VestedRewardsDistributionLike(rewDist).lastDistributedAt();
        if (distTimestamp == 0){
            // first ditribution, we allow to be distributed immediately so there is deadlock
            return block.timestamp - 1;
        }
        else{
            // calculate when distribute() is allowed to be called next and return the value
            return distTimestamp + distributionDelays[rewDist];
        }
    }
}
