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

interface AutoMaxLineLike {
    function autoLine() external returns (address);
    function exec() external returns (
        uint256 oldMaxLine,
        uint256 newMaxLine,
        uint256 debt,
        uint256 oldDuty,
        uint256 newDuty
    );
}

interface AutoLineLike {
    function ilks(bytes32) external view returns (uint256, uint256, uint48, uint48, uint48);
}

/// @title Trigger automaxline updates based on thresholds
contract AutoMaxLineJob is IJob {

    uint256 constant internal BPS = 10 ** 4;
    
    SequencerLike   public immutable sequencer;
    AutoMaxLineLike public immutable automaxline;
    AutoLineLike    public immutable autoline;
    bytes32         public immutable ilk;
    uint256         public immutable thi; // % above the previous max line level
    uint256         public immutable tlo; // % below the previous max line level

    // --- Errors ---
    error NotMaster(bytes32 network);
    error OutsideThreshold(uint256 oldMaxLine, uint256 newMaxLine, uint256 gap);
    error OutsideDebtRange(uint256 oldMaxLine, uint256 newMaxLine, uint256 debt, uint256 gap);

    // --- Events ---
    event Work(bytes32 indexed network);

    constructor(address _sequencer, address _automaxline, bytes32 _ilk, uint256 _thi, uint256 _tlo) {
        sequencer   = SequencerLike(_sequencer);
        automaxline = AutoMaxLineLike(_automaxline);
        autoline    = AutoLineLike(automaxline.autoLine());
        ilk = _ilk;
        thi = _thi;
        tlo = _tlo;
    }

    function work(bytes32 network, bytes calldata) external override {
        if (!sequencer.isMaster(network)) revert NotMaster(network);

        (uint256 oldMaxLine, uint256 newMaxLine, uint256 debt,,) = automaxline.exec();
        (, uint256 gap,,,) = autoline.ilks(ilk); // TODO: should we return gap as well from automaxline to avoid this extra read?

        // Execution is not enough
        // We need to be over the threshold amounts
        if (
            newMaxLine < oldMaxLine + gap * thi / BPS &&
            newMaxLine + gap * tlo / BPS > oldMaxLine
        ) revert OutsideThreshold(oldMaxLine, newMaxLine, gap);

        // In case max line is larger than a single possible gap increase there is no point in moving it yet
        uint256 debtRange = debt + gap;
        if (
            newMaxLine > debtRange &&
            oldMaxLine > debtRange
        ) revert OutsideDebtRange(oldMaxLine, newMaxLine, debt, gap);

        emit Work(network);
    }

    function workable(bytes32 network) external override returns (bool, bytes memory) {
        if (!sequencer.isMaster(network)) return (false, bytes("Network is not master"));

        try this.work(network, "") {
            // Succeeds
            return (true, "");
        } catch {
            // Can not work -- carry on
        }
        return (false, bytes("Work not possible"));
    }

}
