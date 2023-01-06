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
import {D3MJob} from "../D3MJob.sol";

contract VatMock {

    uint256 public art;

    function urns(bytes32, address owner) external view returns (uint256, uint256) {
        return owner == address(123) ? (art, art) : (0, 0);
    }

    function setUrn(bytes32, uint256 _art) external {
        art = _art;
    }
    
}

contract D3MHubMock {

    VatMock public vat;
    uint256 public target;

    constructor(address _vat) {
        vat = VatMock(_vat);
    }

    function setTarget(uint256 _target) external {
        target = _target;
    }

    function pool(bytes32) external pure returns (address) {
        return address(123);
    }

    function exec(bytes32 ilk) external {
        vat.setUrn(ilk, target);
    }
    
}

contract IlkRegistryMock {

    function list() external pure returns (bytes32[] memory ) {
        bytes32[] memory result = new bytes32[](1);
        result[0] = "";
        return result;
    }

}

contract DontExecute {

    function tryWorkable(D3MJob job, bytes32 network) external {
        try job.workable(network)  returns (bool success, bytes memory args) {
            revert(string(abi.encode(success, args)));
        } catch {
        }
    }
    
}

contract D3MJobTest is DssCronBaseTest {

    using GodMode for *;

    VatMock vat;
    IlkRegistryMock ilkRegistryMock;
    D3MHubMock hub;
    DontExecute dontExecute;

    D3MJob d3mJob;

    function setUpSub() virtual override internal {
        vat = new VatMock();
        hub = new D3MHubMock(address(vat));
        ilkRegistryMock = new IlkRegistryMock();
        dontExecute = new DontExecute();

        // Kick off D3M update when things deviate outside 500bps and 10 minutes expiry
        d3mJob = new D3MJob(address(sequencer), address(ilkRegistryMock), address(hub), 500, 10 minutes);
    }

    function getDebt() internal view returns (uint256 art) {
        (, art) = vat.urns("", address(123));
    }

    function isWorkable() internal returns (bool success) {
        try dontExecute.tryWorkable(d3mJob, NET_A) {
            // Should never succeed
        } catch Error(string memory result) {
            (success,) = abi.decode(bytes(result), (bool, bytes));
        }
    }

    function test_zero_to_non_zero() public {
        assertEq(getDebt(), 0);
        assertTrue(!isWorkable());

        hub.setTarget(100 ether);

        assertEq(getDebt(), 0);
        assertTrue(isWorkable());

        d3mJob.work(NET_A, abi.encode(bytes32("")));

        assertEq(getDebt(), 100 ether);
        assertTrue(!isWorkable());
    }

    function test_non_zero_to_zero() public {
        hub.setTarget(100 ether);
        d3mJob.work(NET_A, abi.encode(bytes32("")));
        hub.setTarget(0);
        GodMode.vm().warp(block.timestamp + 10 minutes);

        assertEq(getDebt(), 100 ether);
        assertTrue(isWorkable());

        d3mJob.work(NET_A, abi.encode(bytes32("")));

        assertEq(getDebt(), 0);
        assertTrue(!isWorkable());
    }

    function test_inside_threshold() public {
        hub.setTarget(100 ether);
        d3mJob.work(NET_A, abi.encode(bytes32("")));
        hub.setTarget(99 ether);    // 1% inside threshold

        assertEq(getDebt(), 100 ether);
        assertTrue(!isWorkable());
    }

    function test_outside_threshold() public {
        hub.setTarget(100 ether);
        d3mJob.work(NET_A, abi.encode(bytes32("")));
        hub.setTarget(105 ether);   // 5% outside threshold
        GodMode.vm().warp(block.timestamp + 10 minutes);

        assertEq(getDebt(), 100 ether);
        assertTrue(isWorkable());

        d3mJob.work(NET_A, abi.encode(bytes32("")));

        assertEq(getDebt(), 105 ether);
        assertTrue(!isWorkable());
    }

    function test_inside_timeout() public {
        hub.setTarget(100 ether);
        d3mJob.work(NET_A, abi.encode(bytes32("")));
        hub.setTarget(105 ether);   // 5% outside threshold
        GodMode.vm().warp(block.timestamp + 8 minutes);

        assertEq(getDebt(), 100 ether);
        assertTrue(!isWorkable());
        GodMode.vm().warp(block.timestamp + 2 minutes);
        assertTrue(isWorkable());

        d3mJob.work(NET_A, abi.encode(bytes32("")));

        assertEq(getDebt(), 105 ether);
        assertTrue(!isWorkable());
    }

}
