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

import {TimedJob} from "./base/TimedJob.sol";

interface LerpFactoryLike {
    function count() external view returns (uint256);
    function tall() external;
}

/// @title Tick all lerps
contract LerpJob is TimedJob {
    
    LerpFactoryLike public immutable lerpFactory;

    constructor(address _sequencer, address _lerpFactory, uint256 _duration) TimedJob(_sequencer, _duration) {
        lerpFactory = LerpFactoryLike(_lerpFactory);
    }

    function shouldUpdate() internal override view returns (bool) {
        return lerpFactory.count() > 0;
    }

    function update() internal override {
        lerpFactory.tall();
    }

}
