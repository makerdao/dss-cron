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

contract SequencerTest is DssCronBaseTest {

    address constant ADDR0 = address(123);
    address constant ADDR1 = address(456);
    address constant ADDR2 = address(789);

    event AddNetwork(bytes32 indexed network, uint256 windowSize);
    event RemoveNetwork(bytes32 indexed network);
    event AddJob(address indexed job);
    event RemoveJob(address indexed job);

    function setUpSub() virtual override internal {
        // Remove the default network
        sequencer.removeNetwork(NET_A);
    }

    function test_auth() public {
        checkAuth(address(sequencer), "Sequencer");
    }

    function checkWindow(bytes32 network, uint256 start, uint256 length) internal {
        (uint256 _start, uint256 _length) = sequencer.windows(network);
        assertEq(_start, start);
        assertEq(_length, length);
    }

    function test_add_network() public {
        vm.expectEmit(true, true, true, true);
        emit AddNetwork(NET_A, 123);
        sequencer.addNetwork(NET_A, 123);

        assertEq(sequencer.networkAt(0), NET_A);
        assertTrue(sequencer.hasNetwork(NET_A));
        assertEq(sequencer.numNetworks(), 1);
        assertEq(sequencer.totalWindowSize(), 123);
        checkWindow(NET_A, 0, 123);
    }

    function test_add_dupe_network() public {
        sequencer.addNetwork(NET_A, 123);
        vm.expectRevert(abi.encodeWithSignature("NetworkExists(bytes32)", NET_A));
        sequencer.addNetwork(NET_A, 123);
    }

    function test_add_network_zero_window() public {
        vm.expectRevert(abi.encodeWithSignature("WindowZero(bytes32)", NET_A));
        sequencer.addNetwork(NET_A, 0);
    }

    function test_add_remove_network() public {
        sequencer.addNetwork(NET_A, 123);
        vm.expectEmit(true, true, true, true);
        emit RemoveNetwork(NET_A);
        sequencer.removeNetwork(NET_A);

        assertTrue(!sequencer.hasNetwork(NET_A));
        assertEq(sequencer.numNetworks(), 0);
        assertEq(sequencer.totalWindowSize(), 0);
        checkWindow(NET_A, 0, 0);
    }

    function test_remove_non_existent_network() public {
        sequencer.addNetwork(NET_A, 123);
        vm.expectRevert(abi.encodeWithSignature("NetworkDoesNotExist(bytes32)", NET_B));
        sequencer.removeNetwork(NET_B);
    }

    function test_add_remove_networks() public {
        sequencer.addNetwork(NET_A, 10);
        sequencer.addNetwork(NET_B, 20);
        sequencer.addNetwork(NET_C, 30);

        assertEq(sequencer.numNetworks(), 3);
        assertEq(sequencer.networkAt(0), NET_A);
        assertEq(sequencer.networkAt(1), NET_B);
        assertEq(sequencer.networkAt(2), NET_C);
        assertEq(sequencer.totalWindowSize(), 60);
        checkWindow(NET_A, 0, 10);
        checkWindow(NET_B, 10, 20);
        checkWindow(NET_C, 30, 30);

        // Should move NET_C (last element) to slot 0
        sequencer.removeNetwork(NET_A);

        assertEq(sequencer.numNetworks(), 2);
        assertEq(sequencer.networkAt(0), NET_C);
        assertEq(sequencer.networkAt(1), NET_B);
        assertEq(sequencer.totalWindowSize(), 50);
        checkWindow(NET_C, 0, 30);
        checkWindow(NET_B, 30, 20);
    }

    function test_add_remove_networks_last() public {
        sequencer.addNetwork(NET_A, 10);
        sequencer.addNetwork(NET_B, 20);
        sequencer.addNetwork(NET_C, 10);

        assertEq(sequencer.numNetworks(), 3);
        assertEq(sequencer.networkAt(0), NET_A);
        assertEq(sequencer.networkAt(1), NET_B);
        assertEq(sequencer.networkAt(2), NET_C);
        assertEq(sequencer.totalWindowSize(), 40);
        checkWindow(NET_A, 0, 10);
        checkWindow(NET_B, 10, 20);
        checkWindow(NET_C, 30, 10);

        // Should remove the last element and not re-arrange
        sequencer.removeNetwork(NET_C);

        assertEq(sequencer.numNetworks(), 2);
        assertEq(sequencer.networkAt(0), NET_A);
        assertEq(sequencer.networkAt(1), NET_B);
        assertEq(sequencer.totalWindowSize(), 30);
        checkWindow(NET_A, 0, 10);
        checkWindow(NET_B, 10, 20);
    }

    function test_rotation() public {
        sequencer.addNetwork(NET_A, 3);
        sequencer.addNetwork(NET_B, 7);
        sequencer.addNetwork(NET_C, 25);

        bytes32[3] memory networks = [NET_A, NET_B, NET_C];

        for (uint256 i = 0; i < sequencer.totalWindowSize() * 10; i++) {
            bytes32 master = sequencer.getMaster();
            uint256 pos = block.number % sequencer.totalWindowSize();
            assertTrue(sequencer.isMaster(master));
            assertTrue(sequencer.isMaster(networks[0]) == (pos >= 0 && pos < 3));
            assertTrue(sequencer.isMaster(networks[1]) == (pos >= 3 && pos < 10));
            assertTrue(sequencer.isMaster(networks[2]) == (pos >= 10 && pos < 35));
            assertEq(
                (sequencer.isMaster(networks[0]) ? 1 : 0) +
                (sequencer.isMaster(networks[1]) ? 1 : 0) +
                (sequencer.isMaster(networks[2]) ? 1 : 0)
            , 1);       // Only one active at a time

            vm.roll(block.number + 1);
        }
    }

    function test_add_job() public {
        vm.expectEmit(true, true, true, true);
        emit AddJob(ADDR0);
        sequencer.addJob(ADDR0);

        assertEq(sequencer.jobAt(0), ADDR0);
        assertTrue(sequencer.hasJob(ADDR0));
        assertEq(sequencer.numJobs(), 1);
    }

    function test_add_dupe_job() public {
        sequencer.addJob(ADDR0);
        vm.expectRevert(abi.encodeWithSignature("JobExists(address)", ADDR0));
        sequencer.addJob(ADDR0);
    }

    function test_add_remove_job() public {
        sequencer.addJob(ADDR0);
        vm.expectEmit(true, true, true, true);
        emit RemoveJob(ADDR0);
        sequencer.removeJob(ADDR0);

        assertTrue(!sequencer.hasJob(ADDR0));
        assertEq(sequencer.numJobs(), 0);
    }

    function test_remove_non_existent_job() public {
        sequencer.addJob(ADDR0);
        vm.expectRevert(abi.encodeWithSignature("JobDoesNotExist(address)", ADDR1));
        sequencer.removeJob(ADDR1);
    }

    function test_add_remove_jobs() public {
        sequencer.addJob(ADDR0);
        sequencer.addJob(ADDR1);
        sequencer.addJob(ADDR2);

        assertEq(sequencer.numJobs(), 3);
        assertEq(sequencer.jobAt(0), ADDR0);
        assertEq(sequencer.jobAt(1), ADDR1);
        assertEq(sequencer.jobAt(2), ADDR2);

        // Should move liquidatorJob500 (last element) to slot 0
        sequencer.removeJob(ADDR0);

        assertEq(sequencer.numJobs(), 2);
        assertEq(sequencer.jobAt(0), ADDR2);
        assertEq(sequencer.jobAt(1), ADDR1);
    }

    function test_add_remove_jobs_last() public {
        sequencer.addJob(ADDR0);
        sequencer.addJob(ADDR1);
        sequencer.addJob(ADDR2);

        assertEq(sequencer.numJobs(), 3);
        assertEq(sequencer.jobAt(0), ADDR0);
        assertEq(sequencer.jobAt(1), ADDR1);
        assertEq(sequencer.jobAt(2), ADDR2);

        // Should remove the last element and not re-arrange anything
        sequencer.removeJob(ADDR2);

        assertEq(sequencer.numJobs(), 2);
        assertEq(sequencer.jobAt(0), ADDR0);
        assertEq(sequencer.jobAt(1), ADDR1);
    }

}
