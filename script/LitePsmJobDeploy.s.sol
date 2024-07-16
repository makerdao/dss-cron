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
import {LitePsmJobDeploy, LitePsmJobDeployParams} from "src/deployment/LitePsmJob/LitePsmJobDeploy.sol";
import {LitePsmJobInstance} from "src/deployment/LitePsmJob/LitePsmJobInstance.sol";

contract LitePsmJobDeployScript is Script {
    using stdJson for string;
    using ScriptTools for string;

    string constant NAME = "lite-psm-job-deploy";
    string config;

    address constant CHAINLOG = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;
    DssInstance dss = MCD.loadFromChainlog(CHAINLOG);
    address sequencer = dss.chainlog.getAddress("CRON_SEQUENCER");
    LitePsmJobInstance inst;
    address litePsm;
    uint256 rushThreshold;
    uint256 gushThreshold;
    uint256 cutThreshold;

    function run() external {
        config = ScriptTools.loadConfig();

        litePsm = config.readAddress(".litePsm", "FOUNDRY_LITE_PSM");
        rushThreshold = config.readUint(".rushThreshold", "FOUNDRY_RUSH_THRESHOLD");
        gushThreshold = config.readUint(".gushThreshold", "FOUNDRY_GUSH_THRESHOLD");
        cutThreshold = config.readUint(".cutThreshold", "FOUNDRY_CUT_THRESHOLD");

        vm.startBroadcast();

        inst = LitePsmJobDeploy.deploy(
            LitePsmJobDeployParams({
                sequencer: sequencer,
                litePsm: litePsm,
                rushThreshold: rushThreshold,
                gushThreshold: gushThreshold,
                cutThreshold: cutThreshold
            })
        );

        vm.stopBroadcast();

        ScriptTools.exportContract(NAME, "litePsmJob", inst.job);
        ScriptTools.exportContract(NAME, "sequencer", sequencer);
        ScriptTools.exportContract(NAME, "litePsm", litePsm);
        ScriptTools.exportValue(NAME, "rushThreshold", rushThreshold);
        ScriptTools.exportValue(NAME, "gushThreshold", gushThreshold);
        ScriptTools.exportValue(NAME, "cutThreshold", cutThreshold);
    }
}

