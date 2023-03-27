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
import "dss-interfaces/Interfaces.sol";

import {
    OracleJob,
    PokeLike
} from "../OracleJob.sol";

contract OracleJobIntegrationTest is DssCronBaseTest {

    using GodMode for *;
    using MCD for DssInstance;

    DssIlkInstance ethA;

    OracleJob oracleJob;

    function setUpSub() virtual override internal {
        ethA = dss.getIlk("ETH", "A");
        ethA.pip.src().setWard(address(this), 1);
        MedianAbstract(ethA.pip.src()).kiss(address(this));

        oracleJob = new OracleJob(address(sequencer), address(ilkRegistry), address(dss.spotter));

        // Update all spotters and osms to make sure we are up to date
        vm.warp(block.timestamp + 1 hours);
        bytes32[] memory ilks = ilkRegistry.list();
        for (uint256 i = 0; i < ilks.length; i++) {
            bytes32 ilk = ilks[i];
            address pip = ilkRegistry.pip(ilk);
            if (pip == address(0)) continue;
            try PokeLike(pip).poke() {
            } catch {
            }
        }
        vm.warp(block.timestamp + 1 hours);
        for (uint256 i = 0; i < ilks.length; i++) {
            bytes32 ilk = ilks[i];
            address pip = ilkRegistry.pip(ilk);
            if (pip == address(0)) continue;
            try PokeLike(pip).poke() {
            } catch {
            }
            dss.spotter.poke(ilk);
        }
    }

    function setPrice(address medianizer, uint256 price) internal {
        vm.store(
            address(medianizer),
            bytes32(uint256(1)),
            bytes32(price)
        );
        assertEq(MedianAbstract(medianizer).read(), price, "failed to set price");
    }

    function test_nothing_workable() public {
        (bool canWork,) = oracleJob.workable(NET_A);
        assertEq(canWork, false);
    }

    function test_osm_passed() public {
        vm.warp(block.timestamp + 1 hours);
        uint256 zzz = ethA.pip.zzz();
        (bool canWork, bytes memory args) = oracleJob.workable(NET_A);
        assertEq(canWork, true);
        (address[] memory _toPoke, bytes32[] memory _spotterIlksToPoke) = abi.decode(args, (address[], bytes32[]));
        assertGt(_toPoke.length, 0, "should update all osms");
        assertEq(_spotterIlksToPoke.length, 0, "should not have any spotters to update");
        assertGt(ethA.pip.zzz(), zzz, "should have updated osm");
        (canWork,) = oracleJob.workable(NET_A);
        assertEq(canWork, false);
    }

    function test_price_update() public {
        setPrice(ethA.pip.src(), 123 ether); // $123
        vm.warp(block.timestamp + 1 hours);
        (bool canWork, bytes memory args) = oracleJob.workable(NET_A);
        assertEq(canWork, true);
        (address[] memory _toPoke, bytes32[] memory _spotterIlksToPoke) = abi.decode(args, (address[], bytes32[]));
        assertGt(_toPoke.length, 0);
        assertEq(_spotterIlksToPoke.length, 0);
        vm.warp(block.timestamp + 1 hours);
        (canWork, args) = oracleJob.workable(NET_A);
        assertEq(canWork, true);
        (_toPoke, _spotterIlksToPoke) = abi.decode(args, (address[], bytes32[]));
        assertGt(_toPoke.length, 0);
        assertEq(_spotterIlksToPoke.length, 5); // ETH-A, ETH-B, ETH-C, UNIV2DAIETH-A, UNIV2USDCETH-A, CRVV1ETHSTETH-A
        (,, uint256 spot,,) = dss.vat.ilks(ethA.join.ilk());
        (, uint256 mat) = dss.spotter.ilks(ethA.join.ilk());
        assertEq(spot, 123 * RAD * 10 ** 9 / mat);
        (canWork,) = oracleJob.workable(NET_A);
        assertEq(canWork, false);
    }

}
