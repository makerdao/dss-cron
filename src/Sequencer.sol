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
pragma solidity 0.8.9;

interface JobLike {
    function workable(bytes32 network) external returns (bool canWork, bytes memory args);
}

// Coordination between Keeper Networks
// Only one should be active at a time
// Use the block number to switch between networks
contract Sequencer {

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

    mapping (bytes32 => bool) public networks;
    bytes32[] public activeNetworks;

    mapping (address => bool) public jobs;
    address[] public activeJobs;

    uint256 public window;

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, uint256 data);
    event AddNetwork(bytes32 indexed network);
    event RemoveNetwork(bytes32 indexed network);
    event AddJob(address indexed job);
    event RemoveJob(address indexed job);

    // --- Errors ---
    error InvalidFileParam(bytes32 what);
    error NetworkExists(bytes32 network);
    error JobExists(address job);
    error IndexTooHigh(uint256 index);

    constructor () {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Administration ---
    function file(bytes32 what, uint256 data) external auth {
        if (what == "window") {
            window = data;
        } else revert InvalidFileParam(what);

        emit File(what, data);
    }

    // --- Network Admin ---
    function addNetwork(bytes32 network) external auth {
        if (networks[network]) revert NetworkExists(network);

        activeNetworks.push(network);
        networks[network] = true;

        emit AddNetwork(network);
    }
    function removeNetwork(uint256 index) external auth {
        if (index >= activeNetworks.length) revert IndexTooHigh(index);

        bytes32 network = activeNetworks[index];
        if (index != activeNetworks.length - 1) {
            activeNetworks[index] = activeNetworks[activeNetworks.length - 1];
        }
        activeNetworks.pop();
        networks[network] = false;

        emit RemoveNetwork(network);
    }

    // --- Job Admin ---
    function addJob(address job) external auth {
        if (jobs[job]) revert JobExists(job);

        activeJobs.push(job);
        jobs[job] = true;

        emit AddJob(job);
    }
    function removeJob(uint256 index) external auth {
        if (index >= activeNetworks.length) revert IndexTooHigh(index);

        address job = activeJobs[index];
        if (index != activeJobs.length - 1) {
            activeJobs[index] = activeJobs[activeJobs.length - 1];
        }
        activeJobs.pop();
        jobs[job] = false;

        emit RemoveJob(job);
    }

    // --- Views ---
    function isMaster(bytes32 network) public view returns (bool) {
        if (activeNetworks.length == 0) return false;

        return network == activeNetworks[(block.number / window) % activeNetworks.length];
    }

    function numNetworks() external view returns (uint256) {
        return activeNetworks.length;
    }
    function listAllNetworks() external view returns (bytes32[] memory) {
        return activeNetworks;
    }

    function numJobs() external view returns (uint256) {
        return activeJobs.length;
    }
    function listAllJobs() external view returns (address[] memory) {
        return activeJobs;
    }

    // --- Job helper functions ---
    function getNextJobs(bytes32 network, uint256 startIndex, uint256 endIndexExcl) public returns (WorkableJob[] memory) {
        WorkableJob[] memory _jobs = new WorkableJob[](endIndexExcl - startIndex);
        for (uint256 i = startIndex; i < endIndexExcl; i++) {
            JobLike job = JobLike(activeJobs[i]);
            (bool canWork, bytes memory args) = job.workable(network);
            _jobs[i - startIndex] = WorkableJob(address(job), canWork, args);
        }
        return _jobs;
    }
    function getNextJobs(bytes32 network) external returns (WorkableJob[] memory) {
        return this.getNextJobs(network, 0, activeJobs.length);
    }

}
