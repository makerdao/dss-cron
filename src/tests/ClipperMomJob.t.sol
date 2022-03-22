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

import "./DssCronBase.t.sol";
import {ClipperMomAbstract} from "dss-interfaces/Interfaces.sol";

import {ClipperMomJob} from "../ClipperMomJob.sol";

contract ClipperMomJobTest is DssCronBaseTest {

    using GodMode for *;

    ClipperMomAbstract clipperMom;

    ClipperMomJob clipperMomJob;

    function setUpSub() virtual override internal {
        clipperMom = ClipperMomAbstract(mcd.chainlog().getAddress("CLIPPER_MOM"));

        // Execute all lerps once a day
        clipperMomJob = new ClipperMomJob(address(sequencer), address(ilkRegistry), address(clipperMom));
    }

    function test_no_break() public {
        // By default there should be no clipper that is triggerable except in the very rare circumstance of oracle attack
        (bool canWork,) = clipperMomJob.workable(NET_A);
        assertTrue(!canWork);
    }

    function test_break() public {
        // Place a bad oracle price in the OSM
        uint256 tolerance = clipperMom.tolerance(address(mcd.wethAClip()));
        bytes32 _cur = GodMode.vm().load(
            address(mcd.wethPip()),
            bytes32(uint256(3))
        );
        uint256 cur = uint256(_cur) & type(uint128).max;
        uint256 nxt = cur * tolerance / RAY - 1;
        GodMode.vm().store(
            address(mcd.wethPip()),
            bytes32(uint256(4)),
            bytes32((1 << 128) | nxt)
        );
        
        // Should be able to work and target the ETH-A clipper
        // Workable triggers the actual clipperMom.tripBreaker()
        (bool canWork, bytes memory args) = clipperMomJob.workable(NET_A);
        assertTrue(canWork);
        assertEq(abi.decode(args, (address)), address(mcd.wethAClip()));
        assertEq(mcd.wethAClip().stopped(), 2);
    }

}
