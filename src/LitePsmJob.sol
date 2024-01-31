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

interface LitePsmLike {
    function chug() external returns (uint256 wad);
    function cut() external view returns (uint256 wad);
    function fill() external returns (uint256 wad);
    function gush() external view returns (uint256 wad);
    function rush() external view returns (uint256 wad);
    function trim() external returns (uint256 wad);
    function gem() external returns (address);
    function ilk() external returns (bytes32);
    function vat() external returns (address);
    function buf() external returns (uint256);
}

/// @title Call flap when possible
contract LitePsmJob is IJob {

    SequencerLike public immutable sequencer;
    LitePsmLike public immutable litePsm;

    uint256 public immutable rushThreshold;
    uint256 public immutable cutThreshold;
    uint256 public immutable gushThreshold;

    // --- Errors ---
    error NotMaster(bytes32 network);
    error UnsupportedFunction(bytes4 fn);

    // --- Events ---
    event Work(bytes32 indexed network);

    constructor(address _sequencer, LitePsmLike _litePsm, uint256 _rushThreshold,
                uint256 _cutThreshold, uint256 _gushThreshold) {
        sequencer   = SequencerLike(_sequencer);
        litePsm = _litePsm;
        rushThreshold = _rushThreshold;
        cutThreshold = _cutThreshold;
        gushThreshold = _gushThreshold;
    }

    function work(bytes32 network, bytes calldata args) public {
        if (!sequencer.isMaster(network)) revert NotMaster(network);

        (bytes4 fn) = abi.decode(args, (bytes4));

        if (fn == litePsm.fill.selector && litePsm.rush() > rushThreshold) {
            litePsm.fill();
        }
        else if (fn == litePsm.chug.selector && litePsm.cut() > cutThreshold) {
            litePsm.chug();
        }
        else if  (fn == litePsm.trim.selector && litePsm.gush() > gushThreshold) {
            litePsm.trim();
        }
        else {
            revert UnsupportedFunction(fn);
        }

        emit Work(network);
    }

    function workable(bytes32 network) external view override returns (bool, bytes memory) {
        if (!sequencer.isMaster(network)) return (false, bytes("Network is not master"));

        if (litePsm.rush() > rushThreshold) {
            return (true, abi.encode(litePsm.fill.selector));
        }
        else if (litePsm.cut() > cutThreshold) {
            return (true, abi.encode(litePsm.chug.selector));
        }
        else if (litePsm.gush() > gushThreshold) {
            return (true, abi.encode(litePsm.trim.selector));
        }
        else{
            return (false, bytes("No work to do"));
        }

    }
}
