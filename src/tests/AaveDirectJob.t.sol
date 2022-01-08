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
import {AaveDirectJob} from "../AaveDirectJob.sol";

interface AaveDirectLike {
    function exec() external;
    function file(bytes32,uint256) external;
}

interface LendingPoolLike {
    function getReserveData(address asset) external view returns (
        uint256,    // Configuration
        uint128,    // the liquidity index. Expressed in ray
        uint128,    // variable borrow index. Expressed in ray
        uint128,    // the current supply rate. Expressed in ray
        uint128,    // the current variable borrow rate. Expressed in ray
        uint128,    // the current stable borrow rate. Expressed in ray
        uint40,
        address,    // address of the adai interest bearing token
        address,    // address of the stable debt token
        address,    // address of the variable debt token
        address,    // address of the interest rate strategy
        uint8
    );
}

contract AaveDirectJobTest is DssCronBaseTest {

    uint256 constant ONE_BPS_RAY = 10 ** 23;

    AaveDirectLike aaveDirect;
    LendingPoolLike pool;

    AaveDirectJob aaveDirectJob;

    function setUpSub() virtual override internal {
        aaveDirect = AaveDirectLike(0xa13C0c8eB109F5A13c6c90FC26AFb23bEB3Fb04a);
        pool = LendingPoolLike(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);

        // Kick off D3M update when things deviate outside 50bps
        aaveDirectJob = new AaveDirectJob(address(sequencer), address(aaveDirect), 50 * ONE_BPS_RAY);

        // Give admin to this contract 
        giveAuthAccess(address(aaveDirect), address(this));

        // Empty out the D3M first and match the current aave interest
        aaveDirect.file("bar", 0);
        aaveDirect.exec();
        assertEq(getD3MDebt(), 0);
        aaveDirect.file("bar", getBorrowRate());
        aaveDirect.exec();
        assertEq(getD3MDebt(), 0);
    }

    function getBorrowRate() public view returns (uint256 borrowRate) {
        (,,,, borrowRate,,,,,,,) = pool.getReserveData(address(dai));
    }

    function getD3MDebt() public view returns (uint256 debt) {
        (, debt) = vat.urns(aaveDirectJob.ilk(), address(aaveDirect));
    }

    function test_direct_increase() public {
        bytes memory args;
        (bool canExec, ) = aaveDirectJob.workable(NET_A);
        assertTrue(!canExec, "Should not be able to execute");

        // Decrease the bar by very small amount (10bps) -- should still not trigger
        aaveDirect.file("bar", getBorrowRate() * (BPS - 10) / BPS);
        (canExec, ) = aaveDirectJob.workable(NET_A);
        assertTrue(!canExec, "Should not be able to execute");

        // Decrease the bar over the threshold (100bps) -- should trigger
        aaveDirect.file("bar", getBorrowRate() * (BPS - 100) / BPS);
        (canExec, args) = aaveDirectJob.workable(NET_A);
        assertTrue(canExec, "Should be able to execute");

        // Execute it
        aaveDirectJob.work(NET_A, args);
        assertGt(getD3MDebt(), 0);
    }

}
