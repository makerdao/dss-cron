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
import {AutoLineJob} from "../AutoLineJob.sol";

interface AutoLineLike {
    function vat() external view returns (address);
    function ilks(bytes32) external view returns (uint256, uint256, uint48, uint48, uint48);
    function exec(bytes32) external returns (uint256);
    function setIlk(bytes32,uint256,uint256,uint256) external;
    function remIlk(bytes32) external;
}

contract AutoLineJobTest is DssCronBaseTest {

    AutoLineLike autoline;
    AutoLineJob autoLineJob;

    function setUpSub() virtual override internal {
        autoline = AutoLineLike(0xC7Bdd1F2B16447dcf3dE045C4a039A60EC2f0ba3);
        
        // Setup with 10% / 50% bands
        autoLineJob = new AutoLineJob(address(sequencer), address(ilkRegistry), address(autoline), 1000, 5000);
        
        giveAuthAccess(address(vat), address(this));
        giveAuthAccess(address(autoline), address(this));

        // Setup a dummy ilk in the vat
        vat.init(ILK);
        vat.file(ILK, "spot", RAY);
        vat.file(ILK, "line", 1_000 * RAD);
        autoline.setIlk(ILK, 100_000 * RAD, 1_000 * RAD, 8 hours);

        // Add to ilk regitry as well (only care about the ilk ids array)
        bytes32 pos = bytes32(uint256(5));
        uint256 size = uint256(hevm.load(address(ilkRegistry), pos));
        hevm.store(
            address(ilkRegistry),
            bytes32(uint256(keccak256(abi.encode(pos))) + size),
            ILK
        );      // Append new ilk
        hevm.store(
            address(ilkRegistry),
            pos,
            bytes32(size + 1)
        );      // Increase size of array

        // Clear out any autolines that need to be triggered
        clear_other_ilks(NET_A);
    }

    function clear_other_ilks(bytes32 network) internal {
        while(true) {
            (bool canWork, bytes memory args) = autoLineJob.workable(network);
            if (!canWork) break;
            bytes32 ilk = abi.decode(args, (bytes32));
            if (ilk == ILK) break;
            (,,, uint256 line,) = vat.ilks(ilk);
            autoLineJob.work(network, args);
            (,,, uint256 newLine,) = vat.ilks(ilk);
            assertTrue(line != newLine, "Line should have changed.");
        }
    }

    function mint(bytes32 ilk, uint256 wad) internal {
        (uint256 Art,,,,) = vat.ilks(ilk);
        vat.slip(ilk, address(this), int256(wad));
        vat.frob(ilk, address(this), address(this), address(this), int256(wad), int256(wad));
        (uint256 nextArt,,,,) = vat.ilks(ilk);
        assertEq(nextArt, Art + wad);
    }
    function repay(bytes32 ilk, uint256 wad) internal {
        (uint256 Art,,,,) = vat.ilks(ilk);
        vat.frob(ilk, address(this), address(this), address(this), -int256(wad), -int256(wad));
        vat.slip(ilk, address(this), -int256(wad));
        (uint256 nextArt,,,,) = vat.ilks(ilk);
        assertEq(nextArt, Art - wad);
    }

    function trigger_next_autoline_job(bytes32 network, bytes32 ilk) internal {
        (bool canWork, bytes memory args) = autoLineJob.workable(network);
        assertTrue(canWork, "Expecting to be able to execute.");
        bytes memory expectedArgs = abi.encode(ilk);
        for (uint256 i = 0; i < expectedArgs.length; i++) {
            assertEq(args[i], expectedArgs[i]);
        }
        (,,, uint256 line,) = vat.ilks(ilk);
        autoLineJob.work(network, args);
        (,,, uint256 newLine,) = vat.ilks(ilk);
        assertTrue(line != newLine, "Line should have changed.");
    }

    function verify_no_autoline_job(bytes32 network) internal {
        (bool canWork, bytes memory args) = autoLineJob.workable(network);
        assertTrue(!canWork, "Expecting NOT to be able to execute.");
        bytes memory expectedArgs = "No ilks ready";
        for (uint256 i = 0; i < expectedArgs.length; i++) {
            assertEq(args[i], expectedArgs[i]);
        }
    }

    function test_autolinejob_raise_line() public {
        verify_no_autoline_job(NET_A);

        mint(ILK, 110 * WAD);           // Over the threshold to raise the DC (10%)

        trigger_next_autoline_job(NET_A, ILK);

        verify_no_autoline_job(NET_A);
    }

    function test_autolinejob_disabled() public {
        verify_no_autoline_job(NET_A);

        mint(ILK, 110 * WAD);

        // Disable the autoline
        autoline.remIlk(ILK);

        verify_no_autoline_job(NET_A);
    }

    function test_autolinejob_same_block() public {
        verify_no_autoline_job(NET_A);

        mint(ILK, 200 * WAD);
        trigger_next_autoline_job(NET_A, ILK);
        mint(ILK, 200 * WAD);
        verify_no_autoline_job(NET_A);
    }

    function test_autolinejob_under_ttl() public {
        verify_no_autoline_job(NET_A);

        mint(ILK, 200 * WAD);
        trigger_next_autoline_job(NET_A, ILK);

        hevm.roll(block.number + 1);
        
        // It's possible some other ilks are valid now
        clear_other_ilks(NET_A);

        mint(ILK, 200 * WAD);
        verify_no_autoline_job(NET_A);
    }

    function test_autolinejob_diff_block_ttl() public {
        verify_no_autoline_job(NET_A);

        mint(ILK, 200 * WAD);
        trigger_next_autoline_job(NET_A, ILK);

        hevm.roll(block.number + 1);
        hevm.warp(block.timestamp + 8 hours);
        
        // It's possible some other ilks are valid now
        clear_other_ilks(NET_A);

        mint(ILK, 200 * WAD);
        trigger_next_autoline_job(NET_A, ILK);
    }

    function test_autolinejob_lower_line() public {
        verify_no_autoline_job(NET_A);

        mint(ILK, 1000 * WAD);
        trigger_next_autoline_job(NET_A, ILK);
        hevm.roll(block.number + 1);
        hevm.warp(block.timestamp + 8 hours);
        clear_other_ilks(NET_A);
        mint(ILK, 1000 * WAD);
        trigger_next_autoline_job(NET_A, ILK);
        hevm.roll(block.number + 1);
        repay(ILK, 500 * WAD);      // 50% threshold of gap
        trigger_next_autoline_job(NET_A, ILK);
        verify_no_autoline_job(NET_A);
    }

    function test_autolinejob_autoline_param_change() public {
        // Adjust max line / gap
        autoline.setIlk(ILK, 6_000 * RAD, 5_000 * RAD, 8 hours);

        // Should be triggerable now as we are 1000 away from
        // the line which is 80% above the line - gap
        trigger_next_autoline_job(NET_A, ILK);
    }

    function test_autolinejob_max_line_within_do_nothing_range() public {
        // Set the new gap / maxLine to be slightly less
        autoline.setIlk(ILK, 999 * RAD, 999 * RAD, 8 hours);

        // This should be within the do-nothing range, but should still
        // trigger due to the next adjustment being set to maxLine
        trigger_next_autoline_job(NET_A, ILK);
    }

}
