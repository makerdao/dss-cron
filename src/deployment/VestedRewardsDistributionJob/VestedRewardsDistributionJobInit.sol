// SPDX-FileCopyrightText: © 2023 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: AGPL-3.0-or-later
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

import {ScriptTools} from "dss-test/ScriptTools.sol";
import {VestedRewardsDistributionJob} from "src/VestedRewardsDistributionJob.sol";

struct VestedRewardsDistributionJobInitConfig {
    bytes32 jobKey; // Chainlog key
}

struct VestedRewardsDistributionJobSetDistConfig {
    address dist;
    uint256 interval;
}

struct VestedRewardsDistributionJobRemDistConfig {
    address dist;
}

library VestedRewardsDistributionJobInit {
    ChainlogLike internal constant chainlog = ChainlogLike(0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F);

    function init(address job, VestedRewardsDistributionJobInitConfig memory cfg) internal {
        require(
            VestedRewardsDistributionJobLike(job).sequencer() == chainlog.getAddress("CRON_SEQUENCER"),
            "VestedRewardsDistributionJobInit/invalid-sequencer"
        );
        chainlog.setAddress(cfg.jobKey, job);
    }

    function setDist(address job, VestedRewardsDistributionJobSetDistConfig memory cfg) internal {
        VestedRewardsDistributionJobLike(job).set(cfg.dist, cfg.interval);
    }

    function remDist(address job, VestedRewardsDistributionJobRemDistConfig memory cfg) internal {
        VestedRewardsDistributionJobLike(job).rem(cfg.dist);
    }
}

interface VestedRewardsDistributionJobLike {
    function sequencer() external view returns (address);
    function set(address dist, uint256 interval) external;
    function rem(address dist) external;
}

interface ChainlogLike {
    function getAddress(bytes32 key) external view returns (address);
    function setAddress(bytes32 key, address val) external;
}
