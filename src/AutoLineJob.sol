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

interface IlkRegistryLike {
    function list() external view returns (bytes32[] memory);
}

interface AutoLineLike {
    function vat() external view returns (address);
    function ilks(bytes32) external view returns (uint256, uint256, uint48, uint48, uint48);
    function exec(bytes32) external returns (uint256);
}

interface VatLike {
    function ilks(bytes32) external view returns (uint256, uint256, uint256, uint256, uint256);
}

// Trigger autoline updates based on thresholds
contract AutoLineJob is IJob {

    uint256 constant internal BPS = 10 ** 4;
    
    SequencerLike public immutable sequencer;
    IlkRegistryLike public immutable ilkRegistry;
    AutoLineLike public immutable autoline;
    VatLike public immutable vat;
    uint256 public immutable thi;                       // % above the previously exec'ed debt level
    uint256 public immutable tlo;                       // % below the previously exec'ed debt level

    constructor(address _sequencer, address _ilkRegistry, address _autoline, uint256 _thi, uint256 _tlo) {
        sequencer = SequencerLike(_sequencer);
        ilkRegistry = IlkRegistryLike(_ilkRegistry);
        autoline = AutoLineLike(_autoline);
        vat = VatLike(autoline.vat());
        thi = _thi;
        tlo = _tlo;
    }

    function getNextJob(bytes32 network) external view override returns (bool, address, bytes memory) {
        if (!sequencer.isMaster(network)) return (false, address(0), bytes("Network is not master"));
        
        bytes32[] memory ilks = ilkRegistry.list();
        for (uint256 i = 0; i < ilks.length; i++) {
            bytes32 ilk = ilks[i];

            (uint256 Art, uint256 rate,, uint256 line,) = vat.ilks(ilk);
            uint256 debt = Art * rate;
            (uint256 maxLine, uint256 gap, uint48 ttl, uint48 last, uint48 lastInc) = autoline.ilks(ilk);
            uint256 nextLine = debt + gap;
            if (nextLine > maxLine) nextLine = maxLine;

            // Check autoline rules
            if (maxLine == 0) continue;                                                 // Ilk is not enabled
            if (last == block.number) continue;                                         // Already triggered this block
            if (nextLine > line && block.timestamp < lastInc + ttl) continue;           // TTL hasn't expired

            // Check if nextLine is inside our do-nothing range (special exception if nextLine == maxLine)
            if (nextLine != maxLine && line < nextLine + gap * tlo / BPS && nextLine < line + gap * thi / BPS) continue;
            if (line == maxLine) continue;  // Don't trigger if we are already at maxLine

            // Good to adjust!
            return (true, address(autoline), abi.encodeWithSelector(AutoLineLike.exec.selector, ilk));
        }

        return (false, address(0), bytes("No ilks ready"));
    }

}
