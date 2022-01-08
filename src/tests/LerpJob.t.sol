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
import {LerpJob} from "../LerpJob.sol";

interface LerpFactoryLike {
    function newLerp(bytes32, address, bytes32, uint256, uint256, uint256, uint256) external view returns (address);
    function count() external view returns (uint256);
    function active(uint256) external view returns (address);
}

contract LerpJobTest is DssCronBaseTest {

    LerpFactoryLike lerpFactory;

    LerpJob lerpJob;

    function setUpSub() virtual override internal {
        lerpFactory = LerpFactoryLike(0x9175561733D138326FDeA86CdFdF53e92b588276);

        // Execute all lerps once a day
        lerpJob = new LerpJob(address(sequencer), address(lerpFactory), 1 days);

        // Setup a dummy lerp to track the timestamps
        uint256 start = block.timestamp;
        uint256 end = start + 10 days;
        lerpFactory.newLerp("A TEST", address(vat), "Line", start, start, end, end - start);
    }

    function test_lerp() internal {
        assertTrue(vat.Line() != block.timestamp);      // Randomly this could be false, but seems practically impossible
        
        // Initially should be able to work as the expiry is way in the past
        (bool canWork, bytes memory args) = lerpJob.workable(NET_A);
        assertTrue(canWork, "Should be able to work");
        lerpJob.work(NET_A, args);
        assertEq(vat.Line(), block.timestamp);

        // Cannot call again
        (canWork, args) = lerpJob.workable(NET_A);
        assertTrue(!canWork, "Should not be able to work");

        // Fast forward by 23 hours -- still can't call
        hevm.warp(block.timestamp + 23 hours);
        (canWork, args) = lerpJob.workable(NET_A);
        assertTrue(!canWork, "Should not be able to work");

        // Fast forward by 1 hours -- we can call again
        hevm.warp(block.timestamp + 1 hours);
        (canWork, args) = lerpJob.workable(NET_A);
        assertTrue(canWork, "Should be able to work");
        lerpJob.work(NET_A, args);
        assertEq(vat.Line(), block.timestamp);
    }

}
