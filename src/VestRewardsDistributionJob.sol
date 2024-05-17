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

    SequencerLike public immutable sequencer;


    EnumerableSet.AddressSet private distributions;


    mapping(address => uint256) public distributionIntervals;

    // --- Errors ---
    error CannotDistributeYet(address rewDist);
    error NoArgs();
    error NotMaster(bytes32 network);
    error RewardDistributionExists(address rewDist);
    error RewardDistributionDoesNotExist(address rewDist);

    // --- Events ---
    event Work(bytes32 indexed network, address rewDist, uint distAmounts);
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event AddRewardDistribution(address indexed rewDist, uint256 interval);
    event RemoveRewardDistribution(address indexed rewDist);
    event ModifiedDistributionInterval(address indexed rewDist, uint256 interval);

    constructor(address _sequencer) {
        sequencer = SequencerLike(_sequencer);
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Reward Distribution Admin ---
    function addRewardDistribution(address rewDist, uint256 interval) external auth {
        if (!distributions.add(rewDist)) revert RewardDistributionExists(rewDist);
        distributionIntervals[rewDist] = interval;
        emit AddRewardDistribution(rewDist, interval);
    }

    function removeRewardDistribution(address rewDist) external auth {
        if (!distributions.remove(rewDist)) revert RewardDistributionDoesNotExist(rewDist);
        delete distributionIntervals[rewDist];
        emit RemoveRewardDistribution(rewDist);
    }

    function modifyDistributionInterval(address rewDist, uint256 interval) external auth {
        if (!distributions.contains(rewDist)) revert RewardDistributionDoesNotExist(rewDist);
        distributionIntervals[rewDist] = interval;
        emit ModifiedDistributionInterval(rewDist, interval);
    }

    function work(bytes32 network, bytes calldata args) public {
        if (!sequencer.isMaster(network)) revert NotMaster(network);
        if (args.length == 0) revert NoArgs();

        (address rewDist) = abi.decode(args, (address));

        // prevent keeper from calling random contracts having distribute()
        if (!distributions.contains(rewDist)) revert RewardDistributionDoesNotExist(rewDist);
        // ensure that the right time has elapsed
        if (!canDistribute(rewDist)) revert CannotDistributeYet(rewDist);
        // we omit checking the unpaid amount because if it is 0 it will revert during distribute()
        uint256 distAmount = VestedRewardsDistributionLike(rewDist).distribute();
        emit Work(network, rewDist, distAmount);
    }

    function workable(bytes32 network) external view override returns (bool, bytes memory) {
        if (!sequencer.isMaster(network)) return (false, bytes("Network is not master"));

        uint256 distributionsLen = distributions.length();
        if (distributionsLen > 0) {
            for (uint256 i = 0; i < distributionsLen; i++) {
                address rewDist = distributions.at(i);
                if (canDistribute(rewDist)) return (true, abi.encode(rewDist));
            }
            return (false, bytes("No distribution"));
        }
        return (false, bytes("No farms"));
    }

    function rewardDistributionActive(address rewDist) public view returns (bool) {
        return distributions.contains(rewDist);
    }

    function canDistribute(address rewDist) internal view returns (bool) {
        // get the last time distribute() was called
        uint256 distTimestamp = VestedRewardsDistributionLike(rewDist).lastDistributedAt();
        // if distTimestamp == 0 (first ditribution), we allow to be distributed immediately
        if (distTimestamp + distributionIntervals[rewDist] > block.timestamp || distTimestamp == 0) {
            uint256 vestId = VestedRewardsDistributionLike(rewDist).vestId();
            DssVestWithGemLike dssVest = VestedRewardsDistributionLike(rewDist).dssVest();
            if (dssVest.unpaid(vestId) > 0) return true;
        }
        return false;
    }
}
