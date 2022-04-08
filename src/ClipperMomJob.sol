// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2022 Dai Foundation
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

import {IJob} from "./interfaces/IJob.sol";

interface SequencerLike {
    function isMaster(bytes32 network) external view returns (bool);
}

interface IlkRegistryLike {
    function list() external view returns (bytes32[] memory);
    function info(bytes32 ilk) external view returns (
        string memory name,
        string memory symbol,
        uint256 class,
        uint256 dec,
        address gem,
        address pip,
        address join,
        address xlip
    );
}

interface ClipperMomLike {
    function tripBreaker(address clip) external;
}

/// @title Will trigger a clipper to shutdown if oracle price drops too quickly
contract ClipperMomJob is IJob {
    
    SequencerLike public immutable sequencer;
    IlkRegistryLike public immutable ilkRegistry;
    ClipperMomLike public immutable clipperMom;

    // --- Errors ---
    error NotMaster(bytes32 network);

    constructor(address _sequencer, address _ilkRegistry, address _clipperMom) {
        sequencer = SequencerLike(_sequencer);
        ilkRegistry = IlkRegistryLike(_ilkRegistry);
        clipperMom = ClipperMomLike(_clipperMom);
    }

    function work(bytes32 network, bytes calldata args) external override {
        if (!sequencer.isMaster(network)) revert NotMaster(network);

        clipperMom.tripBreaker(abi.decode(args, (address)));
    }

    function workable(bytes32 network) external override returns (bool, bytes memory) {
        if (!sequencer.isMaster(network)) return (false, bytes("Network is not master"));
        
        bytes32[] memory ilks = ilkRegistry.list();
        for (uint256 i = 0; i < ilks.length; i++) {
            (,, uint256 class,,,,, address clip) = ilkRegistry.info(ilks[i]);
            if (class != 1) continue;
            if (clip == address(0)) continue;

            // We cannot retrieve oracle prices (whitelist-only), so we have to just try and run the trip breaker
            try clipperMom.tripBreaker(clip) {
                // Found a valid trip
                return (true, abi.encode(clip));
            } catch {
                // No valid trip -- carry on
            }
        }

        return (false, bytes("No ilks ready"));
    }

}
