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
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {MCD, DssInstance} from "dss-test/MCD.sol";
import {ScriptTools} from "dss-test/ScriptTools.sol";
import {
    VestedRewardsDistributionJobInit,
    VestedRewardsDistributionJobInitConfig
} from "src/deployment/VestedRewardsDistributionJob/VestedRewardsDistributionJobInit.sol";

contract VestedRewardsDistributionJobInitScript is Script {
    using stdJson for string;
    using ScriptTools for string;

    string constant NAME = "vested-rewards-distribution-init";
    string config;

    address constant CHAINLOG = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;
    DssInstance dss = MCD.loadFromChainlog(CHAINLOG);
    address pauseProxy = dss.chainlog.getAddress("MCD_PAUSE_PROXY");

    function run() external {
        config = ScriptTools.loadConfig();
        address job = config.readAddress(".job", "FOUNDRY_JOB");
        string memory jobKeyStr = config.readString(".jobKey", "FOUNDRY_JOB_KEY");
        bytes32 jobKey = ScriptTools.stringToBytes32(jobKeyStr);

        vm.startBroadcast();

        VestedRewardsDistributionInitSpell spell = new VestedRewardsDistributionInitSpell();
        ProxyLike(pauseProxy).exec(
            address(spell), abi.encodeCall(spell.cast, (job, VestedRewardsDistributionJobInitConfig({jobKey: jobKey})))
        );

        vm.stopBroadcast();

        ScriptTools.exportContract(NAME, "vestedRewardsDistributionJob", job);
        ScriptTools.exportValue(NAME, "vestedRewardsDistributionJobKey", jobKeyStr);
    }
}

contract VestedRewardsDistributionInitSpell {
    function cast(address job, VestedRewardsDistributionJobInitConfig memory cfg) public {
        VestedRewardsDistributionJobInit.init(job, cfg);
    }
}

interface ProxyLike {
    function exec(address usr, bytes memory fax) external returns (bytes memory out);
}
