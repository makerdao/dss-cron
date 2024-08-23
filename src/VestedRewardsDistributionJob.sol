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
contract VestedRewardsDistributionJob is IJob {
    using EnumerableSet for EnumerableSet.AddressSet;

    SequencerLike public immutable sequencer;

    mapping(address => uint256) public wards; // wards[usr]
    mapping(address => uint256) public intervals; // intervals[dist]
    EnumerableSet.AddressSet private distributions;

    // --- Errors ---
    error NotMaster(bytes32 network);
    error NoArgs();
    error InvalidInterval();
    error NotDue(address dist);
    error NotFound(address dist);

    // --- Events ---
    event Work(bytes32 indexed network, address indexed dist, uint256 distAmounts);
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event SetRewardsDistribution(address indexed dist, uint256 interval);
    event RemoveRewardsDistribution(address indexed dist);
    event ModifyDistributionInterval(address indexed dist, uint256 interval);

    constructor(address _sequencer) {
        sequencer = SequencerLike(_sequencer);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Auth ---
    function rely(address usr) external auth {
        wards[usr] = 1;

        emit Rely(usr);
    }

    function deny(address usr) external auth {
        wards[usr] = 0;

        emit Deny(usr);
    }

    modifier auth() {
        require(wards[msg.sender] == 1, "VestedRewardsDistributionJob/not-authorized");
        _;
    }

    // --- Rewards Distribution Admin ---
    function setRewardsDistribution(address dist, uint256 interval) external auth {
        if (interval == 0) revert InvalidInterval();

        if (!distributions.contains(dist)) distributions.add(dist);
        intervals[dist] = interval;
        emit SetRewardsDistribution(dist, interval);
    }

    function removeRewardsDistribution(address dist) external auth {
        if (!distributions.remove(dist)) revert NotFound(dist);

        delete intervals[dist];
        emit RemoveRewardsDistribution(dist);
    }

    function hasRewardsDistribution(address dist) external view returns (bool) {
        return distributions.contains(dist);
    }

    function isRewardsDistributionDue(address dist) public view returns (bool) {
        // Gets the last time distribute() was called
        uint256 distTimestamp = VestedRewardsDistributionLike(dist).lastDistributedAt();
        // If `distTimestamp == 0` (first distribution), we allow it to be distributed immediately
        // Otherwise, if enough time has elapsed since the latest distribution, we also can distribute
        if (distTimestamp == 0 || block.timestamp >= distTimestamp + intervals[dist]) {
            uint256 vestId = VestedRewardsDistributionLike(dist).vestId();
            DssVestWithGemLike dssVest = VestedRewardsDistributionLike(dist).dssVest();
            if (dssVest.unpaid(vestId) > 0) return true;
        }
        return false;
    }

    // --- Keeper network interface ---

    function work(bytes32 network, bytes calldata args) external {
        if (!sequencer.isMaster(network)) revert NotMaster(network);
        if (args.length == 0) revert NoArgs();

        (address dist) = abi.decode(args, (address));

        // Prevents keeper from calling random contracts having distribute()
        if (!distributions.contains(dist)) revert NotFound(dist);
        // Ensures that the right time has elapsed
        if (!isRewardsDistributionDue(dist)) revert NotDue(dist);
        // Omits checking the unpaid amount because if it is 0 it will revert during distribute()
        uint256 distAmount = VestedRewardsDistributionLike(dist).distribute();
        emit Work(network, dist, distAmount);
    }

    function workable(bytes32 network) external override returns (bool, bytes memory) {
        if (!sequencer.isMaster(network)) return (false, bytes("Network is not master"));

        uint256 len = distributions.length();
        if (len > 0) {
            for (uint256 i = 0; i < len; i++) {
                address dist = distributions.at(i);
                if (isRewardsDistributionDue(dist)) {
                    try this.work(network, abi.encode(dist)) {
                        return (true, abi.encode(dist));
                    } catch {
                        // Keeps on looking
                    }
                }
            }
            return (false, bytes("No distribution"));
        }
        return (false, bytes("No farms"));
    }
}
