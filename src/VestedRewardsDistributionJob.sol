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

    /// @notice Keeper Network sequencer.
    SequencerLike public immutable sequencer;

    /// @notice Address with admin access to this contract. wards[usr].
    mapping(address => uint256) public wards;
    /// @notice Minimum intervals between distributions for each dist contract. intervals[dist].
    mapping(address => uint256) public intervals;
    /// @notice Iterable set of dist contracts added to the job.
    EnumerableSet.AddressSet private distributions;

    // --- Errors ---

    /**
     * @notice The keeper trying to execute `work` is not the current master.
     * @param network The keeper identifier.
     */
    error NotMaster(bytes32 network);
    /// @notice No args were provided to `work`.
    error NoArgs();
    /// @notice Trying to set `dist` interval to zero.
    error InvalidInterval();
    /// @notice `wark` was called too early or no vested amount is available.
    error NotDue(address dist);
    /// @notice `dist` was not added to the job.
    error NotFound(address dist);

    // --- Events ---

    /**
     * @notice `usr` was granted admin access.
     * @param usr The user address.
     */
    event Rely(address indexed usr);
    /**
     * @notice `usr` admin access was revoked.
     * @param usr The user address.
     */
    event Deny(address indexed usr);
    /**
     * @notice A `VestedRewardsDistribution` contract was added to or modified in the job.
     * @param dist The dist contract.
     * @param interval The minimum interval between distributions.
     */
    event Set(address indexed dist, uint256 interval);
    /**
     * @notice A dist contract was removed from the job.
     * @param dist The removed dist contract.
     */
    event Rem(address indexed dist);
    /**
     * @notice A dist contract was removed from the job.
     * @param network The keeper who executed the job.
     * @param dist The dist contract where the distribution was made.
     * @param amount The amount distributed.
     */
    event Work(bytes32 indexed network, address indexed dist, uint256 amount);

    /**
     * @param _sequencer The keeper network sequencer.
     */
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

    /**
     * @notice Grants `usr` admin access to this contract.
     * @param usr The user address.
     */
    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }

    /**
     * @notice Revokes `usr` admin access from this contract.
     * @param usr The user address.
     */
    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    // --- Rewards Distribution Admin ---

    /**
     * @notice Adds to the job or updates the interval for distribution for `dist`.
     * @dev `interval` MUST be greater than zero.
     * @param dist The distribution contract.
     * @param interval The interval for distribution.
     */
    function set(address dist, uint256 interval) external auth {
        if (interval == 0) revert InvalidInterval();

        if (!distributions.contains(dist)) distributions.add(dist);
        intervals[dist] = interval;
        emit Set(dist, interval);
    }

    /**
     * @notice Removes `dist` from the job.
     * @param dist The distribution contract.
     */
    function rem(address dist) external auth {
        if (!distributions.remove(dist)) revert NotFound(dist);

        delete intervals[dist];
        emit Rem(dist);
    }

    /**
     * @notice Checks if the job has the specified distribution contract.
     * @param dist The distribution contract.
     * @return Whether `dist` is set in the job or not.
     */
    function has(address dist) public view returns (bool) {
        return distributions.contains(dist);
    }

    /**
     * @notice Checks if the distribution is due for the specified contract.
     * @param dist The distribution contract.
     * @return Whether the distribution is due or not.
     */
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

    /**
     * @notice Executes the job though the keeper network.
     * @param network The keeper identifier.
     * @param args The arguments for execution.
     */
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

    /**
     * @notice Checks if there is work to be done in the job.
     * @param network The keeper identifier.
     * @return ok Whether it should execute or not.
     * @return args The args for execution.
     */
    function workable(bytes32 network) external override returns (bool ok, bytes memory args) {
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
