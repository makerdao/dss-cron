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

contract SequencerTest is DssCronBaseTest {

    address constant ADDR0 = address(0);
    address constant ADDR1 = address(1);
    address constant ADDR2 = address(2);

    function setUpSub() virtual override internal {
        // Remove the default network
        sequencer.removeNetwork(0);
    }

    function test_sequencer_add_network() public {
        sequencer.addNetwork(NET_A);

        assertEq(sequencer.activeNetworks(0), NET_A);
        assertTrue(sequencer.networks(NET_A));
        assertEq(sequencer.numNetworks(), 1);
    }

    function test_sequencer_add_dupe_network() public {
        sequencer.addNetwork(NET_A);
        hevm.expectRevert(abi.encodeWithSignature("NetworkExists(bytes32)", NET_A));
        sequencer.addNetwork(NET_A);
    }

    function test_sequencer_add_remove_network() public {
        sequencer.addNetwork(NET_A);
        sequencer.removeNetwork(0);

        assertTrue(!sequencer.networks(NET_A));
        assertEq(sequencer.numNetworks(), 0);
    }

    function test_sequencer_add_remove_networks() public {
        sequencer.addNetwork(NET_A);
        sequencer.addNetwork(NET_B);
        sequencer.addNetwork(NET_C);

        assertEq(sequencer.numNetworks(), 3);
        assertEq(sequencer.activeNetworks(0), NET_A);
        assertEq(sequencer.activeNetworks(1), NET_B);
        assertEq(sequencer.activeNetworks(2), NET_C);

        // Should move NET_C (last element) to slot 0
        sequencer.removeNetwork(0);

        assertEq(sequencer.numNetworks(), 2);
        assertEq(sequencer.activeNetworks(0), NET_C);
        assertEq(sequencer.activeNetworks(1), NET_B);
    }

    function test_sequencer_add_remove_networks_last() public {
        sequencer.addNetwork(NET_A);
        sequencer.addNetwork(NET_B);
        sequencer.addNetwork(NET_C);

        assertEq(sequencer.numNetworks(), 3);
        assertEq(sequencer.activeNetworks(0), NET_A);
        assertEq(sequencer.activeNetworks(1), NET_B);
        assertEq(sequencer.activeNetworks(2), NET_C);

        // Should remove the last element and not re-arrange
        sequencer.removeNetwork(2);

        assertEq(sequencer.numNetworks(), 2);
        assertEq(sequencer.activeNetworks(0), NET_A);
        assertEq(sequencer.activeNetworks(1), NET_B);
    }

    function test_sequencer_rotation() public {
        sequencer.addNetwork(NET_A);
        sequencer.addNetwork(NET_B);
        sequencer.addNetwork(NET_C);

        bytes32[3] memory networks = [NET_A, NET_B, NET_C];

        for (uint256 i = 0; i < sequencer.window() * 10; i++) {
            assertTrue(sequencer.isMaster(networks[0]) == ((block.number / sequencer.window()) % sequencer.numNetworks() == 0));
            assertTrue(sequencer.isMaster(networks[1]) == ((block.number / sequencer.window()) % sequencer.numNetworks() == 1));
            assertTrue(sequencer.isMaster(networks[2]) == ((block.number / sequencer.window()) % sequencer.numNetworks() == 2));
            assertEq(
                (sequencer.isMaster(networks[0]) ? 1 : 0) +
                (sequencer.isMaster(networks[1]) ? 1 : 0) +
                (sequencer.isMaster(networks[2]) ? 1 : 0)
            , 1);       // Only one active at a time

            hevm.roll(block.number + 1);
        }
    }

    function test_sequencer_add_job() public {
        sequencer.addJob(ADDR0);

        assertEq(sequencer.activeJobs(0), ADDR0);
        assertTrue(sequencer.jobs(ADDR0));
        assertEq(sequencer.numJobs(), 1);
    }

    function test_sequencer_add_dupe_job() public {
        sequencer.addJob(ADDR0);
        hevm.expectRevert(abi.encodeWithSignature("JobExists(address)", ADDR0));
        sequencer.addJob(ADDR0);
    }

    function test_sequencer_add_remove_job() public {
        sequencer.addJob(ADDR0);
        sequencer.removeJob(0);

        assertTrue(!sequencer.jobs(ADDR0));
        assertEq(sequencer.numJobs(), 0);
    }

    function test_sequencer_add_remove_jobs() public {
        sequencer.addJob(ADDR0);
        sequencer.addJob(ADDR1);
        sequencer.addJob(ADDR2);

        assertEq(sequencer.numJobs(), 3);
        assertEq(sequencer.activeJobs(0), ADDR0);
        assertEq(sequencer.activeJobs(1), ADDR1);
        assertEq(sequencer.activeJobs(2), ADDR2);

        // Should move liquidatorJob500 (last element) to slot 0
        sequencer.removeJob(0);

        assertEq(sequencer.numJobs(), 2);
        assertEq(sequencer.activeJobs(0), ADDR2);
        assertEq(sequencer.activeJobs(1), ADDR1);
    }

    function test_sequencer_add_remove_jobs_last() public {
        sequencer.addJob(ADDR0);
        sequencer.addJob(ADDR1);
        sequencer.addJob(ADDR2);

        assertEq(sequencer.numJobs(), 3);
        assertEq(sequencer.activeJobs(0), ADDR0);
        assertEq(sequencer.activeJobs(1), ADDR1);
        assertEq(sequencer.activeJobs(2), ADDR2);

        // Should remove the last element and not re-arrange anything
        sequencer.removeJob(2);

        assertEq(sequencer.numJobs(), 2);
        assertEq(sequencer.activeJobs(0), ADDR0);
        assertEq(sequencer.activeJobs(1), ADDR1);
    }

}
