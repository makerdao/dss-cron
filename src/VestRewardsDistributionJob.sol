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
    function vestId() external view returns (uint256);
    function dssVest() external view returns (DssVestWithGemLike);
    function distribute() external returns (uint256 amount);
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

    EnumerableSet.AddressSet private distributions;

    SequencerLike public immutable sequencer;

    // --- Errors ---
    error NotMaster(bytes32 network);
    error RewardDistributionExists(address farm);
    error RewardDistributionDoesNotExist(address farm);

    // --- Events ---
    event Work(bytes32 indexed network);
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event AddRewardDistribution(address indexed rewdist);
    event RemoveRewardDistribution(address indexed rewDist);

    constructor(
        address _sequencer
    ) {
        sequencer = SequencerLike(_sequencer);
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Reward Distribution Admin ---
    function addRewardDistribution(address rewdist) external auth {
        if (!distributions.add(rewdist)) revert RewardDistributionExists(rewdist);
        emit AddRewardDistribution(rewdist);
    }

    function removeRewardDistribution(address rewdist) external auth {
        if (!distributions.remove(rewdist)) revert RewardDistributionDoesNotExist(rewdist);
        emit RemoveRewardDistribution(rewdist);
    }

    function work(bytes32 network, bytes calldata args) public {
        if (!sequencer.isMaster(network)) revert NotMaster(network);

        (address[] memory vestingfarms) = abi.decode(args, (address[]));

        for (uint256 i = 0; i < vestingfarms.length; i++) {
            VestedRewardsDistributionLike(vestingfarms[i]).distribute();
        }
        emit Work(network);
    }

    function workable(bytes32 network) external view override returns (bool, bytes memory) {
        if (!sequencer.isMaster(network)) return (false, bytes("Network is not master"));

        uint256 distributionsLen = distributions.length();
        if (distributionsLen > 0) {
            address[] memory vestingFarms = new address[](distributionsLen);
            for (uint256 i = 0; i < distributionsLen; i++) {
                address farm = distributions.at(i);
                uint256 vestId = VestedRewardsDistributionLike(farm).vestId();
                DssVestWithGemLike dssVest = VestedRewardsDistributionLike(farm).dssVest();
                uint256 amount = dssVest.unpaid(vestId);
                if (amount > 0)
                    vestingFarms[i] = farm;
                else
                    vestingFarms[i] = address(0);
            }
            return (true, abi.encode(vestingFarms));

        }
        else {
            return (false, bytes("No farms"));
        }
    }

    function rewardDistributionActive(address rewDist) public view returns (bool) {
        return distributions.contains(rewDist);
    }

}
