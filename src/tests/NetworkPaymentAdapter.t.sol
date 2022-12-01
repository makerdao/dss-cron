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
        dai = DaiMock;
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

    NetworkPaymentAdapter public adapter;

    constructor(NetworkPaymentAdapter _adapter) {
        adapter = _adapter;
    }

    function topUp() external {
        adapter.topUp();
    }

}

contract NetworkPaymentAdapter is DSSTest {

    VestMock vest;
    TreasuryMock treasury;
    DaiMock dai;
    DaiJoinMock daiJoin;
    VatMock vat;
    address vow;

    NetworkPaymentAdapter adapter;

    function postSetup() internal virtual override {
        vest = new VestMock();
        treasury = new TreasuryMock();
        dai = new DaiMock();
        vat = new VatMock();
        daiJoin = new DaiJoinMock(address(vat), address(dai));
        vow = TEST_ADDRESS;

        adapter = new NetworkPaymentAdapter(
            address(vest),
            123,
            address(treasury),
            address(daiJoin),
            vow
        );
    }

    function test_auth() public {
        checkAuth(address(adapter), address(this));
    }

}
