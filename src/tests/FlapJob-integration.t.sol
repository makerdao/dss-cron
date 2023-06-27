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

import {FlapJob} from "../FlapJob.sol";

contract FlapJobIntegrationTest is DssCronBaseTest {
    using stdStorage for StdStorage;
    using GodMode for *;

    FlapJob flapJob;

    event LogNote(
        bytes4   indexed  sig,
        address  indexed  usr,
        bytes32  indexed  arg1,
        bytes32  indexed  arg2,
        bytes             data
    ) anonymous;

    function setUpSub() virtual override internal {
        flapJob = new FlapJob(address(sequencer), address(dss.vat), address(dss.vow), tx.gasprice);

        // Make sure that if a flapper has a cooldown period it already passed
        GodMode.vm().warp(block.timestamp + 10 days);

        // Set default values that assure flap will succeed without a need to heal
        stdstore.target(address(dss.vat)).sig("dai(address)").with_key(address(dss.vow)).depth(0).checked_write(70 * MILLION * RAD);
        stdstore.target(address(dss.vat)).sig("sin(address)").with_key(address(dss.vow)).depth(0).checked_write(uint256(0));
        stdstore.target(address(dss.vow)).sig("hump()").checked_write(50 * MILLION * RAD);
        stdstore.target(address(dss.vow)).sig("bump()").checked_write(10 * THOUSAND * RAD);
        stdstore.target(address(dss.vow)).sig("Sin()").checked_write(uint256(0));
        stdstore.target(address(dss.vow)).sig("Ash()").checked_write(uint256(0));

    }

    function test_flap_no_need_to_heal() public {
        uint256 snapshot = vm.snapshot();
        (bool canWork, bytes memory args) = flapJob.workable(NET_A);
        assertTrue(canWork, "Should be able to work");
        vm.revertTo(snapshot);

        vm.expectEmit(false, false, false, false);
        emit LogNote(dss.vow.flap.selector, address(0), 0, 0, bytes(""));
        flapJob.work(NET_A, args);
    }

    function test_flap_need_to_heal() public {
        // force free bad debt of 1
        uint256 newVatSin = dss.vow.Sin() + dss.vow.Ash() + 1;
        stdstore.target(address(dss.vat)).sig("sin(address)").with_key(address(dss.vow)).depth(0).checked_write(newVatSin);

        uint256 snapshot = vm.snapshot();
        (bool canWork, bytes memory args) = flapJob.workable(NET_A);
        assertTrue(canWork, "Should be able to work");
        vm.revertTo(snapshot);

        vm.expectEmit(false, false, false, false);
        emit LogNote(dss.vow.heal.selector, address(0), 0, 0, bytes(""));
        vm.expectEmit(false, false, false, false);
        emit LogNote(dss.vow.flap.selector, address(0), 0, 0, bytes(""));
        flapJob.work(NET_A, args);
    }

    function test_flap_heal_fails() public {
        // force system surplus to be negative
        uint256 newVatSin = dss.vat.dai(address(dss.vow)) + 1;
        stdstore.target(address(dss.vat)).sig("sin(address)").with_key(address(dss.vow)).depth(0).checked_write(newVatSin);

        (bool canWork,) = flapJob.workable(NET_A);
        assertTrue(!canWork, "Should not be able to work");
    }

    function test_flap_fails() public {
        // force hump to be higher than the SB
        uint256 newVowHump = dss.vat.dai(address(dss.vow)) + 1;
        stdstore.target(address(dss.vow)).sig("hump()").checked_write(newVowHump);

        (bool canWork,) = flapJob.workable(NET_A);
        assertTrue(!canWork, "Should not be able to work");
    }

    function test_flap_gasPriceTooHigh() public {
        flapJob = new FlapJob(address(sequencer), address(dss.vat), address(dss.vow), tx.gasprice - 1);

        (bool canWork,) = flapJob.workable(NET_A);
        assertTrue(!canWork, "Should not be able to work");
    }
}
