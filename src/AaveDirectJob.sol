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

import {IJob} from "./interfaces/IJob.sol";

interface SequencerLike {
    function isMaster(bytes32 network) external view returns (bool);
}

interface VatLike {
    function ilks(bytes32) external view returns (uint256, uint256, uint256, uint256, uint256);
    function urns(bytes32, address) external view returns (uint256, uint256);
}

interface DirectLike {
    function vat() external view returns (address);
    function pool() external view returns (address);
    function dai() external view returns (address);
    function adai() external view returns (address);
    function stableDebt() external view returns (address);
    function variableDebt() external view returns (address);
    function bar() external view returns (uint256);
    function ilk() external view returns (bytes32);
    function exec() external;
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

/// @title Trigger Aave D3M updates based on threshold
contract AaveDirectJob is IJob {

    uint256 constant internal RAY = 10 ** 27;
    
    SequencerLike public immutable sequencer;
    DirectLike public immutable direct;
    VatLike public immutable vat;
    address public immutable dai;
    bytes32 public immutable ilk;
    LendingPoolLike public immutable pool;
    uint256 public immutable threshold;         // Threshold deviation to kick off exec [RAY units]

    // --- Errors ---
    error NotMaster(bytes32 network);
    error OutsideThreshold();

    // --- Events ---
    event Work(bytes32 indexed network);

    constructor(address _sequencer, address _direct, uint256 _threshold) {
        sequencer = SequencerLike(_sequencer);
        direct = DirectLike(_direct);
        vat = VatLike(direct.vat());
        dai = direct.dai();
        ilk = direct.ilk();
        pool = LendingPoolLike(direct.pool());
        threshold = _threshold;
    }

    function isOutsideThreshold() internal view returns (bool) {
        // IMPORTANT: this function assumes Vat rate of this ilk will always be == 1 * RAY (no fees).
        // That's why this module converts normalized debt (art) to Vat DAI generated with a simple RAY multiplication or division
        // This module will have an unintended behaviour if rate is changed to some other value.

        (, uint256 daiDebt) = vat.urns(ilk, address(direct));
        uint256 _bar = direct.bar();
        if (_bar == 0) {
            return daiDebt > 1;     // Always attempt to close out if we have debt remaining
        }

        (,,,, uint256 currVarBorrow,,,,,,,) = pool.getReserveData(dai);

        uint256 deviation = currVarBorrow * RAY / _bar;
        if (deviation < RAY) {
            // Unwind case
            return daiDebt > 1 && (RAY - deviation) > threshold;
        } else if (deviation > RAY) {
            // Wind case
            (,,, uint256 line,) = vat.ilks(ilk);
            return (daiDebt + 1)*RAY < line && (deviation - RAY) > threshold;
        } else {
            // No change
            return false;
        }
    }

    function work(bytes32 network, bytes calldata) external override {
        if (!sequencer.isMaster(network)) revert NotMaster(network);
        if (!isOutsideThreshold()) revert OutsideThreshold();

        direct.exec();

        emit Work(network);
    }

    function workable(bytes32 network) external view override returns (bool, bytes memory) {
        if (!sequencer.isMaster(network)) return (false, bytes("Network is not master"));
        if (!isOutsideThreshold()) return (false, bytes("Interest rate is in acceptable range"));

        return (true, "");
    }

}
