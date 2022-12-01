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

import "dss-test/DSSTest.sol";

import {DaiMock} from "./mocks/DaiMock.sol";
import {DaiJoinMock} from "./mocks/DaiJoinMock.sol";
import {VatMock} from "./mocks/VatMock.sol";
import {NetworkPaymentAdapter} from "../NetworkPaymentAdapter.sol";

contract VestMock {

    mapping (uint256 => uint256) public vests;
    DaiMock public dai;

    constructor(DaiMock _dai) {
        dai = _dai;
    }

    function setVest(uint256 id, uint256 amt) external {
        vests[id] = amt;
    }

    function vest(uint256 id) external {
        dai.transfer(msg.sender, vests[id]);
        vests[id] = 0;
    }

    function unpaid(uint256 id) external view returns (uint256) {
        return vests[id];
    }

}

contract TreasuryMock {

    DaiMock public dai;

    constructor(DaiMock _dai) {
        dai = _dai;
    }

    function topUp(NetworkPaymentAdapter adapter) external returns (uint256) {
        return adapter.topUp();
    }

    function getBufferSize() external view returns (uint256) {
        return dai.balanceOf(address(this));
    }

}

contract NetworkPaymentAdapterTest is DSSTest {

    uint256 constant VEST_ID = 123;

    VestMock vest;
    TreasuryMock treasury;
    DaiMock dai;
    DaiJoinMock daiJoin;
    VatMock vat;
    address vow;

    NetworkPaymentAdapter adapter;

    function setUp() public {
        dai = new DaiMock();
        vat = new VatMock();
        daiJoin = new DaiJoinMock(address(vat), address(dai));
        vest = new VestMock(dai);
        treasury = new TreasuryMock(dai);
        vow = TEST_ADDRESS;

        dai.rely(address(daiJoin));

        vat.suck(address(this), address(this), 10_000 * RAD);
        vat.hope(address(daiJoin));
        daiJoin.exit(address(vest), 10_000 ether);

        adapter = new NetworkPaymentAdapter(
            address(vest),
            VEST_ID,
            address(treasury),
            address(daiJoin),
            vow
        );
    }

    function test_auth() public {
        checkAuth(address(adapter), "NetworkPaymentAdapter");
    }

    function test_file() public {
        checkFileUint(address(adapter), "NetworkPaymentAdapter", ["bufferMax", "minimumPayment"]);
    }

    function test_topUp() public {
        uint256 vestAmount = 100 ether;
        vest.setVest(VEST_ID, vestAmount);
        adapter.file("bufferMax", 1000 ether);
        adapter.file("minimumPayment", 100 ether);

        assertTrue(adapter.canTopUp());
        assertEq(dai.balanceOf(address(treasury)), 0);
        assertEq(treasury.getBufferSize(), 0);

        uint256 daiSent = treasury.topUp(adapter);

        assertEq(daiSent, vestAmount);
        assertTrue(!adapter.canTopUp());
        assertEq(dai.balanceOf(address(treasury)), vestAmount);
        assertEq(treasury.getBufferSize(), vestAmount);
    }

    function test_topUpMultiple() public {
        uint256 vestAmount = 100 ether;
        vest.setVest(VEST_ID, vestAmount);
        adapter.file("bufferMax", 1000 ether);
        adapter.file("minimumPayment", 100 ether);

        treasury.topUp(adapter);
        vest.setVest(VEST_ID, vestAmount);

        assertTrue(adapter.canTopUp());
        assertEq(dai.balanceOf(address(treasury)), vestAmount);
        assertEq(treasury.getBufferSize(), vestAmount);

        uint256 daiSent = treasury.topUp(adapter);

        assertEq(daiSent, vestAmount);
        assertEq(dai.balanceOf(address(treasury)), 2 * vestAmount);
        assertEq(treasury.getBufferSize(), 2 * vestAmount);
    }

    function test_topUpOverMax() public {
        uint256 vestAmount = 100 ether;
        vest.setVest(VEST_ID, vestAmount);
        adapter.file("bufferMax", 60 ether);
        adapter.file("minimumPayment", 10 ether);

        assertTrue(adapter.canTopUp());
        assertEq(dai.balanceOf(address(treasury)), 0);
        assertEq(treasury.getBufferSize(), 0);
        assertEq(vat.dai(vow), 0);

        uint256 daiSent = treasury.topUp(adapter);

        assertEq(daiSent, 60 ether);
        assertEq(dai.balanceOf(address(treasury)), 60 ether);
        assertEq(treasury.getBufferSize(), 60 ether);
        assertEq(vat.dai(vow), 40 * RAD);
    }

    function test_topUpBufferFull() public {
        vest.setVest(VEST_ID, 90 ether + 1);
        adapter.file("bufferMax", 100 ether);
        adapter.file("minimumPayment", 10 ether);
        treasury.topUp(adapter);
        vest.setVest(VEST_ID, 90 ether);
        assertTrue(!adapter.canTopUp());

        vm.expectRevert(abi.encodeWithSignature("BufferFull(uint256,uint256,uint256)", 90 ether + 1, 10 ether, 100 ether));
        treasury.topUp(adapter);
    }

    function test_topUpPendingDaiTooSmall() public {
        vest.setVest(VEST_ID, 5 ether);
        adapter.file("bufferMax", 100 ether);
        adapter.file("minimumPayment", 10 ether);
        assertTrue(!adapter.canTopUp());

        vm.expectRevert(abi.encodeWithSignature("PendingDaiTooSmall(uint256,uint256)", 5 ether, 10 ether));
        treasury.topUp(adapter);
    }

}
