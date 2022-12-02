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

import "./utils/EnumerableSet.sol";

interface JobLike {
    function workable(bytes32 network) external returns (bool canWork, bytes memory args);
}

/// @title Coordination between Keeper Networks
/// @dev Only one should be active at a time
///
/// Use the block number to switch between networks
contract Sequencer {

    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    struct Window {
        uint256 start;
        uint256 length;
    }

    struct WorkableJob {
        address job;
        bool canWork;
        bytes args;
    }

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
        require(wards[msg.sender] == 1, "Sequencer/not-authorized");
        _;
    }

    EnumerableSet.Bytes32Set private networks;
    EnumerableSet.AddressSet private jobs;
    mapping(bytes32 => Window) public windows;
    uint256 public totalWindowSize;

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event AddNetwork(bytes32 indexed network, uint256 windowSize);
    event RemoveNetwork(bytes32 indexed network);
    event AddJob(address indexed job);
    event RemoveJob(address indexed job);

    // --- Errors ---
    error WindowZero(bytes32 network);
    error NetworkExists(bytes32 network);
    error NetworkDoesNotExist(bytes32 network);
    error JobExists(address job);
    error JobDoesNotExist(address network);
    error IndexTooHigh(uint256 index, uint256 length);
    error BadIndicies(uint256 startIndex, uint256 exclEndIndex);

    constructor () {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Network Admin ---
    function refreshStarts() internal {
        uint256 start = 0;
        uint256 netLen = networks.length();
        for (uint256 i = 0; i < netLen; i++) {
            bytes32 network = networks.at(i);
            windows[network].start = start;
            start += windows[network].length;
        }
    }
    function addNetwork(bytes32 network, uint256 windowSize) external auth {
        if (!networks.add(network)) revert NetworkExists(network);
        if (windowSize == 0) revert WindowZero(network);
        windows[network] = Window({
            start: 0,               // start will be set in refreshStarts
            length: windowSize
        });
        totalWindowSize += windowSize;
        refreshStarts();
        emit AddNetwork(network, windowSize);
    }
    function removeNetwork(bytes32 network) external auth {
        if (!networks.remove(network)) revert NetworkDoesNotExist(network);
        uint256 windowSize = windows[network].length;
        delete windows[network];
        totalWindowSize -= windowSize;
        refreshStarts();
        emit RemoveNetwork(network);
    }

    // --- Job Admin ---
    function addJob(address job) external auth {
        if (!jobs.add(job)) revert JobExists(job);
        emit AddJob(job);
    }
    function removeJob(address job) external auth {
        if (!jobs.remove(job)) revert JobDoesNotExist(job);
        emit RemoveJob(job);
    }

    // --- Views ---
    function isMaster(bytes32 network) external view returns (bool) {
        if (networks.length() == 0) return false;

        Window memory window = windows[network];
        uint256 pos = block.number % totalWindowSize;
        return window.start <= pos && pos < window.start + window.length;
    }
    function getMaster() external view returns (bytes32) {
        uint256 netLen = networks.length();
        if (netLen == 0) return bytes32(0);

        uint256 pos = block.number % totalWindowSize;
        for (uint256 i = 0; i < netLen; i++) {
            bytes32 network = networks.at(i);
            Window memory window = windows[network];
            if (window.start <= pos && pos < window.start + window.length) {
                return network;
            }
        }
        return bytes32(0);
    }

    function numNetworks() external view returns (uint256) {
        return networks.length();
    }
    function hasNetwork(bytes32 network) public view returns (bool) {
        return networks.contains(network);
    }
    function networkAt(uint256 index) public view returns (bytes32) {
        return networks.at(index);
    }

    function numJobs() external view returns (uint256) {
        return jobs.length();
    }
    function hasJob(address job) public view returns (bool) {
        return jobs.contains(job);
    }
    function jobAt(uint256 index) public view returns (address) {
        return jobs.at(index);
    }

    // --- Job helper functions ---
    function getNextJobs(bytes32 network, uint256 startIndex, uint256 endIndexExcl) public returns (WorkableJob[] memory) {
        if (endIndexExcl < startIndex) revert BadIndicies(startIndex, endIndexExcl);
        uint256 length = jobs.length();
        if (endIndexExcl > length) revert IndexTooHigh(endIndexExcl, length);
        
        WorkableJob[] memory _jobs = new WorkableJob[](endIndexExcl - startIndex);
        for (uint256 i = startIndex; i < endIndexExcl; i++) {
            JobLike job = JobLike(jobs.at(i));
            (bool canWork, bytes memory args) = job.workable(network);
            _jobs[i - startIndex] = WorkableJob(address(job), canWork, args);
        }
        return _jobs;
    }
    function getNextJobs(bytes32 network) external returns (WorkableJob[] memory) {
        return getNextJobs(network, 0, jobs.length());
    }

}
