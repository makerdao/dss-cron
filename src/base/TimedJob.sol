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

import {IJob} from "../interfaces/IJob.sol";

interface SequencerLike {
    function isMaster(bytes32 network) external view returns (bool);
}

/// @title A job that executes at a fixed interval
/// @dev Extend this contract to easily execute some action at a fixed interval
abstract contract TimedJob is IJob {
    
    SequencerLike public immutable sequencer;
    uint256 public immutable maxDuration;       // The max duration between ticks
    uint256 public last;

    // --- Errors ---
    error NotMaster(bytes32 network);
    error TimerNotElapsed(uint256 currentTime, uint256 expiry);
    error ShouldUpdateIsFalse();

    // --- Events ---
    event Work(bytes32 indexed network);

    constructor(address _sequencer, uint256 _maxDuration) {
        sequencer = SequencerLike(_sequencer);
        maxDuration = _maxDuration;
    }

    function work(bytes32 network, bytes calldata) external {
        if (!sequencer.isMaster(network)) revert NotMaster(network);
        uint256 expiry = last + maxDuration;
        if (block.timestamp < expiry) revert TimerNotElapsed(block.timestamp, expiry);
        if (!shouldUpdate()) revert ShouldUpdateIsFalse();
        
        last = block.timestamp;
        update();

        emit Work(network);
    }

    function workable(bytes32 network) external view override returns (bool, bytes memory) {
        if (!sequencer.isMaster(network)) return (false, bytes("Network is not master"));
        if (block.timestamp < last + maxDuration) return (false, bytes("Timer hasn't elapsed"));
        if (!shouldUpdate()) return (false, bytes("shouldUpdate is false"));
        
        return (true, "");
    }

    function shouldUpdate() virtual internal view returns (bool);
    function update() virtual internal;

}
