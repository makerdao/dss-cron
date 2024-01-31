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

import {LitePsmJob} from "../LitePsmJob.sol";
import {LitePsmLike} from "../LitePsmJob.sol";

interface DaiAbstract {
    function balanceOf(address) external view returns (uint256);
}

interface GemLike {
    function balanceOf(address) external view returns (uint256);
    function decimals() external view returns (uint8);
    function approve(address, uint256) external;
    function transfer(address, uint256) external;
    function transferFrom(address, address, uint256) external;
}

interface VatLike {
    function frob(bytes32, address, address, address, int256, int256) external;
    function hope(address) external;
    function slip(bytes32, address, int256) external;
    function ilks(bytes32) external view returns (uint256, uint256, uint256, uint256, uint256);
    function debt() external view returns (uint256);
    function Line() external view returns (uint256);
    function urns(bytes32, address) external view returns (uint256, uint256);
}

contract LitePsmJobIntegrationTest is DssCronBaseTest {

    using GodMode for *;

    LitePsmLike public litePsm;
    LitePsmJob public litePsmJob;
    address public gem;
    address public dai;
    address public pocket;

    // --- Events ---
    event Chug(uint256 wad);
    event Trim(uint256 wad);
    event Work(bytes32 indexed network);

    function setUpSub() virtual override internal {
        litePsm = LitePsmLike(dss.chainlog.getAddress("MCD_LITE_PSM_USDC_A"));
        pocket = dss.chainlog.getAddress("MCD_LITE_PSM_POCKET_USDC_A");
        dai = dss.chainlog.getAddress("MCD_DAI");

        litePsmJob = new LitePsmJob(address(sequencer), litePsm, 1_000_000e18, 1_000_000e18, 1_000_000e18);

        gem = litePsm.gem();
    }

    // function test_fill() public {
    //     uint256 amount = 10_000_000e18;
    //     deal(gem, pocket, amount);
    //     uint256 wad = litePsm.rush();
    //     assertEq(wad, 0);
    //     deal(gem, pocket, amount);
    //     uint256 newWad = litePsm.rush();
    //     assertEq(newWad, amount);
    //     (bool canWork, bytes memory args) = litePsmJob.workable(NET_A);
    //     if (canWork){
    //         (bytes4 fn) = abi.decode(args, (bytes4));
    //         bytes4 encodedSelector = bytes4(abi.encode(litePsm.fill.selector));
    //         assertEq(fn, encodedSelector);
    //     }
    // }

     function test_chug() public {
        address vat_ = litePsm.vat();
        bytes32 ilk = litePsm.ilk();
        (, uint256 art) = VatLike(vat_).urns(ilk, address(litePsm));
        deal(dai, address(litePsm), art + 1); //must be greater than art so we dont have underflow
        uint256 wad = litePsm.cut();
        assertTrue(wad != 0);
        (bool canWork, bytes memory args) = litePsmJob.workable(NET_A);
        if (canWork){
            (bytes4 fn) = abi.decode(args, (bytes4));
            bytes4 encodedSelector = bytes4(abi.encode(litePsm.chug.selector));
            assertEq(fn, encodedSelector);
            vm.expectEmit(false, false, false, true);
            emit Chug(wad);
            vm.expectEmit(true, false, false, false);
            emit Work(NET_A);
            litePsmJob.work(NET_A, args);
            wad = litePsm.cut();
            assertEq(wad, 0);
        }
    }

    function test_trim() public {
        uint256 amount = 10_000_000_000e18;
        deal(dai, address(litePsm), amount);
        deal(gem, pocket, 0);
        uint256 wad = litePsm.gush();
        assertTrue(wad != 0);
        (bool canWork, bytes memory args) = litePsmJob.workable(NET_A);
        if (canWork){
            (bytes4 fn) = abi.decode(args, (bytes4));
            bytes4 encodedSelector = bytes4(abi.encode(litePsm.trim.selector));
            assertEq(fn, encodedSelector);
            vm.expectEmit(false, false, false, true);
            emit Trim(wad);
            vm.expectEmit(true, false, false, false);
            emit Work(NET_A);
            litePsmJob.work(NET_A, args);
            wad = litePsm.gush();
            assertEq(wad, 0);
        }
    }

}
