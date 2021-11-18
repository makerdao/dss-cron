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
pragma solidity ^0.8.9;

import "./IJob.sol";

interface SequencerLike {
    function isMaster(bytes32 network) external view returns (bool);
}

interface AutoLineLike {
    function exec(bytes32) external returns (uint256);
}

interface IlkRegistryLike {
    function list() external view returns (bytes32[] memory);
}

// Trigger autoline updates based on thresholds
contract AutoLineJob is IJob {
    
    SequencerLike public immutable sequencer;
    IlkRegistryLike public immutable ilkRegistry;
    AutoLineLike public immutable autoline;
    uint256 public immutable tlo;
    uint256 public immutable thi;

    constructor(address _sequencer, address _ilkRegistry, address _autoline, uint256 _tlo, uint256 _thi) {
        sequencer = SequencerLike(_sequencer);
        ilkRegistry = IlkRegistryLike(_ilkRegistry);
        autoline = AutoLineLike(_autoline);
        tlo = _tlo;
        thi = _thi;
    }

    function getNextJob(bytes32 network) external view override returns (bool, address, bytes memory) {
        if (!sequencer.isMaster(network)) return (false, address(0), bytes("Network is not master"));
        
        bytes32[] memory ilks = ilkRegistry.list();
        for (uint256 i = 0; i < ilks.length; i++) {
            bytes32 ilk = ilks[i];

            // TODO evaluate lower/raise DCs
        }

        return (false, address(0), bytes("No ilks ready"));
    }

}
