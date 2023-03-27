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
pragma solidity 0.8.13;

import {IJob} from "./interfaces/IJob.sol";

interface SequencerLike {
    function isMaster(bytes32 network) external view returns (bool);
}

interface IlkRegistryLike {
    function list() external view returns (bytes32[] memory);
    function pip(bytes32 ilk) external view returns (address);
}

interface VatLike {
    function ilks(bytes32 ilk) external view returns (
        uint256 Art,
        uint256 rate,
        uint256 spot,
        uint256 line,
        uint256 dust
    );
}

interface PokeLike {
    function poke() external;
}

interface SpotterLike {
    function vat() external view returns (address);
    function poke(bytes32 ilk) external;
}

/// @title Triggers osm / oracle updates for all ilks
contract OracleJob is IJob {
    
    SequencerLike public immutable sequencer;
    IlkRegistryLike public immutable ilkRegistry;
    VatLike public immutable vat;
    SpotterLike public immutable spotter;

    // Don't actually store anything
    address[] private toPoke;
    bytes32[] private spotterIlksToPoke;

    // --- Errors ---
    error NotMaster(bytes32 network);
    error NotSuccessful();

    // --- Events ---
    event Work(bytes32 indexed network, address[] toPoke, bytes32[] spotterIlksToPoke, uint256 numSuccessful);

    constructor(address _sequencer, address _ilkRegistry, address _spotter) {
        sequencer = SequencerLike(_sequencer);
        ilkRegistry = IlkRegistryLike(_ilkRegistry);
        spotter = SpotterLike(_spotter);
        vat = VatLike(spotter.vat());
    }

    function work(bytes32 network, bytes calldata args) external override {
        if (!sequencer.isMaster(network)) revert NotMaster(network);

        (address[] memory _toPoke, bytes32[] memory _spotterIlksToPoke) = abi.decode(args, (address[], bytes32[]));
        uint256 numSuccessful = 0;
        for (uint256 i = 0; i < _toPoke.length; i++) {
            try PokeLike(_toPoke[i]).poke() {
                numSuccessful++;
            } catch {
            }
        }
        for (uint256 i = 0; i < _spotterIlksToPoke.length; i++) {
            bytes32 ilk = _spotterIlksToPoke[i];
            (uint256 Art,,  uint256 beforeSpot, uint256 line,) = vat.ilks(ilk);
            if (Art == 0 && line == 0) continue;
            spotter.poke(ilk);
            (,,  uint256 afterSpot,,) = vat.ilks(ilk);
            if (beforeSpot != afterSpot) {
                numSuccessful++;
            }
        }

        if (numSuccessful == 0) revert NotSuccessful();

        emit Work(network, _toPoke, _spotterIlksToPoke, numSuccessful);
    }

    function workable(bytes32 network) external override returns (bool, bytes memory) {
        if (!sequencer.isMaster(network)) return (false, bytes("Network is not master"));

        delete toPoke;
        delete spotterIlksToPoke;
        
        bytes32[] memory ilks = ilkRegistry.list();
        for (uint256 i = 0; i < ilks.length; i++) {
            bytes32 ilk = ilks[i];
            PokeLike pip = PokeLike(ilkRegistry.pip(ilk));

            if (address(pip) == address(0)) continue;

            // Just try to poke the oracle and add to the list if it works
            // This won't add an OSM twice
            try pip.poke() {
                toPoke.push(address(pip));
            } catch {
            }

            // See if the spot price changes
            (uint256 Art,,  uint256 beforeSpot, uint256 line,) = vat.ilks(ilk);
            if (Art == 0 && line == 0) continue; // Skip if no debt / line
            spotter.poke(ilk);
            (,,  uint256 afterSpot,,) = vat.ilks(ilk);
            if (beforeSpot != afterSpot) {
                spotterIlksToPoke.push(ilk);
            }
        }

        if (toPoke.length > 0 || spotterIlksToPoke.length > 0) {
            return (true, abi.encode(toPoke, spotterIlksToPoke));
        } else {
            return (false, bytes("No ilks ready"));
        }
    }

}
