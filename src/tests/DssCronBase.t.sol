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

import "dss-test/DssTest.sol";
import {IlkRegistryAbstract} from "dss-interfaces/Interfaces.sol";

import {Sequencer} from "../Sequencer.sol";
import {LiquidatorJob} from "../LiquidatorJob.sol";
import {LerpJob} from "../LerpJob.sol";

// Integration tests against live MCD
abstract contract DssCronBaseTest is DssTest {

    using MCD for DssInstance;

    bytes32 constant NET_A = "NTWK-A";
    bytes32 constant NET_B = "NTWK-B";
    bytes32 constant NET_C = "NTWK-C";
    bytes32 constant ILK = "TEST-ILK";

    IlkRegistryAbstract ilkRegistry;
    Sequencer sequencer;

    DssInstance dss;

    MCDUser user;

    function setUp() public {
        dss = MCD.loadFromChainlog(0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F);

        sequencer = new Sequencer();

        ilkRegistry = IlkRegistryAbstract(dss.chainlog.getAddress("ILK_REGISTRY"));

        // Add a default network
        sequencer.addNetwork(NET_A, 13);
        assertEq(sequencer.totalWindowSize(), 13);
        (uint256 start, uint256 length) = sequencer.windows(NET_A);
        assertEq(start, 0);
        assertEq(length, 13);

        // Add a default user
        user = dss.newUser();

        setUpSub();
    }

    function setUpSub() virtual internal;

}
