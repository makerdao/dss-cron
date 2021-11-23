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

import "ds-test/test.sol";
import {Sequencer} from "./Sequencer.sol";
import {AutoLineJob} from "./AutoLineJob.sol";

interface Hevm {
    function warp(uint256) external;
    function roll(uint256) external;
    function store(address,bytes32,bytes32) external;
    function load(address,bytes32) external view returns (bytes32);
}

interface AuthLike {
    function wards(address) external returns (uint256);
}

interface IlkRegistryLike {
    function list() external view returns (bytes32[] memory);
}

interface AutoLineLike {
    function vat() external view returns (address);
    function ilks(bytes32) external view returns (uint256, uint256, uint48, uint48, uint48);
    function exec(bytes32) external returns (uint256);
    function setIlk(bytes32,uint256,uint256,uint256) external;
}

interface VatLike {
    function ilks(bytes32) external view returns (uint256, uint256, uint256, uint256, uint256);
    function slip(bytes32, address, int256) external;
    function frob(bytes32, address, address, address, int256, int256) external;
    function init(bytes32) external;
    function file(bytes32, bytes32, uint256) external;
}

// Integration tests against live MCD
contract DssCronTest is DSTest {

    uint256 constant WAD = 10 ** 18;
    uint256 constant RAY = 10 ** 27;
    uint256 constant RAD = 10 ** 45;

    Hevm hevm;

    IlkRegistryLike ilkRegistry;
    AutoLineLike autoline;
    VatLike vat;
    Sequencer sequencer;

    // Jobs
    AutoLineJob autoLineJob;

    bytes32 constant NET_A = "NTWK-A";
    bytes32 constant NET_B = "NTWK-B";
    bytes32 constant NET_C = "NTWK-C";
    bytes32 constant ILK = "TEST-ILK";

    function setUp() public {
        hevm = Hevm(HEVM_ADDRESS);

        sequencer = new Sequencer();
        sequencer.file("window", 12);       // Give 12 block window for each network (~3 mins)
        assertEq(sequencer.window(), 12);

        ilkRegistry = IlkRegistryLike(0x5a464C28D19848f44199D003BeF5ecc87d090F87);
        autoline = AutoLineLike(0xC7Bdd1F2B16447dcf3dE045C4a039A60EC2f0ba3);
        vat = VatLike(0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B);
        autoLineJob = new AutoLineJob(address(sequencer), address(ilkRegistry), address(autoline), 1000, 2000);     // 10% / 20% bands

    }

    function giveAuthAccess(address _base, address target) internal {
        AuthLike base = AuthLike(_base);

        // Edge case - ward is already set
        if (base.wards(target) == 1) return;

        for (int i = 0; i < 100; i++) {
            // Scan the storage for the ward storage slot
            bytes32 prevValue = hevm.load(
                address(base),
                keccak256(abi.encode(target, uint256(i)))
            );
            hevm.store(
                address(base),
                keccak256(abi.encode(target, uint256(i))),
                bytes32(uint256(1))
            );
            if (base.wards(target) == 1) {
                // Found it
                return;
            } else {
                // Keep going after restoring the original value
                hevm.store(
                    address(base),
                    keccak256(abi.encode(target, uint256(i))),
                    prevValue
                );
            }
        }

        // We have failed if we reach here
        assertTrue(false);
    }

    function test_sequencer_add_network() public {
        sequencer.addNetwork(NET_A);

        assertEq(sequencer.activeNetworks(0), NET_A);
        assertTrue(sequencer.networks(NET_A));
        assertEq(sequencer.count(), 1);
    }

    function testFail_sequencer_add_dupe_network() public {
        sequencer.addNetwork(NET_A);
        sequencer.addNetwork(NET_A);
    }

    function test_sequencer_add_remove_network() public {
        sequencer.addNetwork(NET_A);
        sequencer.removeNetwork(0);

        assertTrue(!sequencer.networks(NET_A));
        assertEq(sequencer.count(), 0);
    }

    function test_sequencer_add_remove_networks() public {
        sequencer.addNetwork(NET_A);
        sequencer.addNetwork(NET_B);
        sequencer.addNetwork(NET_C);

        assertEq(sequencer.count(), 3);
        assertEq(sequencer.activeNetworks(0), NET_A);
        assertEq(sequencer.activeNetworks(1), NET_B);
        assertEq(sequencer.activeNetworks(2), NET_C);

        // Should move NET_C (last element) to slot 0
        sequencer.removeNetwork(0);


        assertEq(sequencer.count(), 2);
        assertEq(sequencer.activeNetworks(0), NET_C);
        assertEq(sequencer.activeNetworks(1), NET_B);
    }

    function test_sequencer_rotation() public {
        sequencer.addNetwork(NET_A);
        sequencer.addNetwork(NET_B);
        sequencer.addNetwork(NET_C);

        bytes32[3] memory networks = [NET_A, NET_B, NET_C];

        for (uint256 i = 0; i < sequencer.window() * 10; i++) {
            assertTrue(sequencer.isMaster(networks[0]) == ((block.number / sequencer.window()) % sequencer.count() == 0));
            assertTrue(sequencer.isMaster(networks[1]) == ((block.number / sequencer.window()) % sequencer.count() == 1));
            assertTrue(sequencer.isMaster(networks[2]) == ((block.number / sequencer.window()) % sequencer.count() == 2));
            assertEq(
                (sequencer.isMaster(networks[0]) ? 1 : 0) +
                (sequencer.isMaster(networks[1]) ? 1 : 0) +
                (sequencer.isMaster(networks[2]) ? 1 : 0)
            , 1);       // Only one active at a time

            hevm.roll(block.number + 1);
        }
    }

    // --- AutoLineJob tests ---

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

    function init_autoline() internal {
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

        // Add a default network
        sequencer.addNetwork(NET_A);

        // Clear out any autolines that need to be triggered
        while(true) {
            (bool canExec, address target, bytes memory execPayload) = autoLineJob.getNextJob(NET_A);
            if (!canExec) break;
            bytes32 ilk = abi.decode(execPayload, (bytes32));
            (,,, uint256 line,) = vat.ilks(ilk);
            (bool success, bytes memory result) = target.call(execPayload);
            uint256 newLine = abi.decode(result, (uint256));
            assertTrue(success, "Execution should have succeeded.");
            assertTrue(line != newLine, "Line should have changed.");
        }
    }

    function trigger_next_autoline_job(bytes32 network, bytes32 ilk) internal {
        (bool canExec, address target, bytes memory execPayload) = autoLineJob.getNextJob(network);
        assertTrue(canExec, "Expecting to be able to execute.");
        assertEq(target, address(autoline));
        bytes memory expectedPayload = abi.encodeWithSelector(AutoLineLike.exec.selector, ilk);
        for (uint256 i = 0; i < expectedPayload.length; i++) {
            assertEq(execPayload[i], expectedPayload[i]);
        }
        (,,, uint256 line,) = vat.ilks(ilk);
        (bool success, bytes memory result) = target.call(execPayload);
        uint256 newLine = abi.decode(result, (uint256));
        assertTrue(success, "Execution should have succeeded.");
        assertTrue(line != newLine, "Line should have changed.");
    }

    function verify_no_autoline_job() internal {
        (bool canExec, address target,) = autoLineJob.getNextJob(network);
        assertTrue(canExec);
        assertEq(target, address(0));
    }

    function test_autolinejob_raise_line() public {
        init_autoline();

        verify_no_autoline_job();

        mint(ILK, 110 * WAD);           // Over the threshold to raise the DC (10%)

        trigger_next_autoline_job(NET_A, ILK);

        verify_no_autoline_job();
    }

}
