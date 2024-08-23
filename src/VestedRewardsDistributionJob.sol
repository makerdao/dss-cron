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
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Set(address indexed dist, uint256 interval);
    event Rem(address indexed dist);
    event Work(bytes32 indexed network, address indexed dist, uint256 amount);

    constructor(address _sequencer) {
        sequencer = SequencerLike(_sequencer);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Auth ---
    modifier auth() {
        require(wards[msg.sender] == 1, "VestedRewardsDistributionJob/not-authorized");
        _;
    }

    function rely(address usr) external auth {
        wards[usr] = 1;

        emit Rely(usr);
    }

    function deny(address usr) external auth {
        wards[usr] = 0;

        emit Deny(usr);
    }

    // --- Rewards Distribution Admin ---
    function set(address dist, uint256 interval) external auth {
        if (interval == 0) revert InvalidInterval();

        if (!distributions.contains(dist)) distributions.add(dist);
        intervals[dist] = interval;
        emit Set(dist, interval);
    }

    function rem(address dist) external auth {
        if (!distributions.remove(dist)) revert NotFound(dist);

        delete intervals[dist];
        emit Rem(dist);
    }

    function has(address dist) public view returns (bool) {
        return distributions.contains(dist);
    }

    function due(address dist) public view returns (bool) {
        // Gets the last time distribute() was called
        uint256 last = VestedRewardsDistributionLike(dist).lastDistributedAt();
        // If `last == 0` (no distribution so far), we allow it to be distributed immediately,
        // otherwise, we can only distribute if enough time has elapsed since the last one.
        if (last != 0 && block.timestamp < last + intervals[dist]) return false;

        uint256 vestId = VestedRewardsDistributionLike(dist).vestId();
        DssVestWithGemLike vest = VestedRewardsDistributionLike(dist).dssVest();
        // Distribution is only due if there are unpaid tokens.
        return vest.unpaid(vestId) > 0;
    }

    // --- Keeper Network Interface ---
    function work(bytes32 network, bytes calldata args) external {
        if (!sequencer.isMaster(network)) revert NotMaster(network);
        if (args.length == 0) revert NoArgs();

        (address dist) = abi.decode(args, (address));
        // Prevents keeper from calling random contracts with a `distribute` method.
        if (!has(dist)) revert NotFound(dist);
        // Ensures that enough time has passed.
        if (!due(dist)) revert NotDue(dist);

        uint256 amount = VestedRewardsDistributionLike(dist).distribute();
        emit Work(network, dist, amount);
    }

    function workable(bytes32 network) external override returns (bool, bytes memory) {
        if (!sequencer.isMaster(network)) return (false, bytes("Network is not master"));

        uint256 len = distributions.length();
        for (uint256 i = 0; i < len; i++) {
            address dist = distributions.at(i);
            if (!due(dist)) continue;

            try this.work(network, abi.encode(dist)) {
                return (true, abi.encode(dist));
            } catch {
                continue;
            }
        }
        return (false, bytes("No distribution"));
    }
}
