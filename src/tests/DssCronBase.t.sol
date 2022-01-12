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

import "dss-test/DSSTest.sol";
import {IlkRegistryAbstract} from "dss-interfaces/Interfaces.sol";

import {Sequencer} from "../Sequencer.sol";
import {LiquidatorJob} from "../LiquidatorJob.sol";
import {LerpJob} from "../LerpJob.sol";

// Integration tests against live MCD
abstract contract DssCronBaseTest is DSSTest {

    bytes32 constant NET_A = "NTWK-A";
    bytes32 constant NET_B = "NTWK-B";
    bytes32 constant NET_C = "NTWK-C";
    bytes32 constant ILK = "TEST-ILK";

    IlkRegistryAbstract ilkRegistry;
    Sequencer sequencer;

    MCDUser user;

    function setupEnv() internal virtual override returns (MCD) {
        return new MCDMainnet();
    }

    function postSetup() internal virtual override {
        sequencer = new Sequencer();
        sequencer.file("window", 12);       // Give 12 block window for each network (~3 mins)
        assertEq(sequencer.window(), 12);

        ilkRegistry = IlkRegistryAbstract(mcd.chainlog().getAddress("ILK_REGISTRY"));
        
        // Add a default network
        sequencer.addNetwork(NET_A);

        // Add a default user
        user = mcd.newUser();
        
        setUpSub();
    }

    function setUpSub() virtual internal;

}
