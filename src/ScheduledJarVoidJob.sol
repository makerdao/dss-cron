// SPDX-FileCopyrightText: © 2022 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Copyright (C) 2021-2022 Dai Foundation
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

import {TimedJob} from "./base/TimedJob.sol";

import "dss-interfaces/dss/DaiAbstract.sol";

interface RwaJarLike {
    function daiJoin() external returns(address);
    function dai() external returns(address);
    function chainlog() external returns(address);
    function void() external;
    function toss(uint256) external;
}

/**
 * @author David Krett <david@w2d.co>
 * @title ScheduledJarVoidJob
 * @dev checks the balance in a Jar and if above a threshold balance voids the jar
 */
contract ScheduledJarVoidJob is TimedJob {
    
    RwaJarLike public immutable rwaJar;

    DaiAbstract public immutable dai;

    uint256 public constant THRESHOLD = 500 * (10 ** 18);

    constructor(address _sequencer, address _jar, uint256 _duration) TimedJob(_sequencer, _duration) {
        rwaJar = RwaJarLike(_jar);
        dai = DaiAbstract(rwaJar.dai());
    }

    /**
    * @notice checks the designated jar balance and indicates whether it needs to be voided.
    * @param .
    */
    function shouldUpdate() internal override view returns (bool) {
        uint256 balance = dai.balanceOf(address(rwaJar));
        if (balance > THRESHOLD) {
            return true;
        }
        return false;
    }

    /**
    * @notice voids the designated Jar.
    */
    function update() internal override {
        rwaJar.void();
    }
}