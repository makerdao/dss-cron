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

interface SequencerLike {
    function isMaster(bytes32 network) external view returns (bool);
}

interface IlkRegistryLike {
    function list() external view returns (bytes32[] memory);
}

interface VatLike {
    function urns(bytes32, address) external view returns (uint256, uint256);
}

interface D3MHubLike {
    function vat() external view returns (VatLike);
    function pool(bytes32) external view returns (address);
    function exec(bytes32) external;
}

/// @title Trigger D3M updates based on threshold
contract D3MJob is IJob {

    uint256 constant internal BPS = 10 ** 4;
    
    SequencerLike public immutable sequencer;
    IlkRegistryLike public immutable ilkRegistry;
    D3MHubLike public immutable hub;
    VatLike public immutable vat;
    uint256 public immutable threshold;             // Threshold deviation to kick off exec [BPS]
    uint256 public immutable ttl;                   // Cooldown before you can call exec again [seconds]

    mapping (bytes32 => uint256) public expiry;     // Timestamp of when exec is allowed again

    // --- Errors ---
    error NotMaster(bytes32 network);
    error Cooldown(bytes32 ilk, uint256 expiry);
    error ShouldNotTrigger(bytes32 ilk, uint256 part, uint256 nart);

    // --- Events ---
    event Work(bytes32 indexed network);

    constructor(address _sequencer, address _ilkRegistry, address _hub, uint256 _threshold, uint256 _ttl) {
        sequencer = SequencerLike(_sequencer);
        ilkRegistry = IlkRegistryLike(_ilkRegistry);
        hub = D3MHubLike(_hub);
        vat = hub.vat();
        threshold = _threshold;
        ttl = _ttl;
    }

    function shouldTrigger(uint256 part, uint256 nart) internal view returns (bool) {
        if (part == 0 && nart != 0) return true;    // From zero to non-zero
        if (part != 0 && nart == 0) return true;    // From non-zero to zero
        if (part == 0 && nart == 0) return false;   // No change at zero

        // Check if the delta is above the threshold
        uint256 delta = nart * BPS / part;
        if (delta < BPS) delta = BPS * BPS / delta; // Flip decreases to increase

        return delta >= (BPS + threshold);
    }

    function work(bytes32 network, bytes calldata args) external override {
        if (!sequencer.isMaster(network)) revert NotMaster(network);

        bytes32 ilk = abi.decode(args, (bytes32));
        uint256 _expiry = expiry[ilk];
        if (block.timestamp < _expiry) revert Cooldown(ilk, _expiry);
        address pool = hub.pool(ilk);
        (, uint256 part) = vat.urns(ilk, pool);

        hub.exec(ilk);

        (, uint256 nart) = vat.urns(ilk, pool);
        if (!shouldTrigger(part, nart)) revert ShouldNotTrigger(ilk, part, nart);
        
        expiry[ilk] = block.timestamp + ttl;

        emit Work(network);
    }

    function workable(bytes32 network) external override returns (bool, bytes memory) {
        if (!sequencer.isMaster(network)) return (false, bytes("Network is not master"));

        bytes32[] memory ilks = ilkRegistry.list();
        for (uint256 i = 0; i < ilks.length; i++) {
            bytes memory args = abi.encode(ilks[i]);
            try this.work(network, args) {
                // Found a valid execution
                return (true, args);
            } catch {
                // For some reason this errored -- carry on
            }
        }

        return (false, bytes("No ilks ready"));
    }

}
