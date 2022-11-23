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

import "./DssCronBase.t.sol";
import {ClipperMomAbstract,ClipAbstract} from "dss-interfaces/Interfaces.sol";

import {ClipperMomJob} from "../ClipperMomJob.sol";

contract ClipperMomJobIntegrationTest is DssCronBaseTest {

    using GodMode for *;

    ClipperMomAbstract clipperMom;

    ClipperMomJob clipperMomJob;

    function setUpSub() virtual override internal {
        clipperMom = ClipperMomAbstract(mcd.chainlog().getAddress("CLIPPER_MOM"));

        // Execute all lerps once a day
        clipperMomJob = new ClipperMomJob(address(sequencer), address(ilkRegistry), address(clipperMom));
    }

    function set_bad_price(address clip, address pip) internal {
        uint256 tolerance = clipperMom.tolerance(clip);
        bytes32 _cur = GodMode.vm().load(
            address(pip),
            bytes32(uint256(3))
        );
        uint256 cur = uint256(_cur) & type(uint128).max;
        uint256 nxt = cur * tolerance / RAY - 1;
        GodMode.vm().store(
            address(pip),
            bytes32(uint256(4)),
            bytes32((1 << 128) | nxt)
        );
    }

    function test_no_break() public {
        // By default there should be no clipper that is triggerable except in the very rare circumstance of oracle attack
        (bool canWork,) = clipperMomJob.workable(NET_A);
        assertTrue(!canWork);
    }

    function test_break() public {
        // Place a bad oracle price in the OSM
        set_bad_price(address(mcd.wethAClip()), address(mcd.wethPip()));
        
        // Should be able to work and target the ETH-A clipper
        // Workable triggers the actual clipperMom.tripBreaker()
        assertEq(mcd.wethAClip().stopped(), 0);
        (bool canWork, bytes memory args) = clipperMomJob.workable(NET_A);
        assertTrue(canWork);
        assertEq(abi.decode(args, (address)), address(mcd.wethAClip()));
        assertEq(mcd.wethAClip().stopped(), 2);
    }

    function test_break_work() public {
        // Place a bad oracle price in the OSM
        set_bad_price(address(mcd.wethAClip()), address(mcd.wethPip()));
        
        // Test the actual work function
        assertEq(mcd.wethAClip().stopped(), 0);
        clipperMomJob.work(NET_A, abi.encode(address(mcd.wethAClip())));
        assertEq(mcd.wethAClip().stopped(), 2);
    }

    function test_break_multiple() public {
        // Place a bad oracle price in the OSM
        set_bad_price(address(mcd.wethAClip()), address(mcd.wethPip()));
        
        // Should be able to trigger 3 clips
        ClipAbstract wethBClip = ClipAbstract(mcd.chainlog().getAddress("MCD_CLIP_ETH_B"));
        ClipAbstract wethCClip = ClipAbstract(mcd.chainlog().getAddress("MCD_CLIP_ETH_C"));

        // ETH-A
        assertEq(mcd.wethAClip().stopped(), 0);
        (bool canWork, bytes memory args) = clipperMomJob.workable(NET_A);
        assertTrue(canWork);
        assertEq(abi.decode(args, (address)), address(mcd.wethAClip()));
        assertEq(mcd.wethAClip().stopped(), 2);

        // ETH-B
        assertEq(wethBClip.stopped(), 0);
        (canWork, args) = clipperMomJob.workable(NET_A);
        assertTrue(canWork);
        assertEq(abi.decode(args, (address)), address(wethBClip));
        assertEq(wethBClip.stopped(), 2);

        // ETH-C
        assertEq(wethCClip.stopped(), 0);
        (canWork, args) = clipperMomJob.workable(NET_A);
        assertTrue(canWork);
        assertEq(abi.decode(args, (address)), address(wethCClip));
        assertEq(wethCClip.stopped(), 2);
    }

}
