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

import "forge-std/Test.sol";
import "./DssCronBase.t.sol";

import {LitePsmLike} from "../LitePsmJob.sol";
import {LitePsmJob} from "../LitePsmJob.sol";

interface LitePsm {
    function chug() external returns (uint256 wad);
    function cut() external view returns (uint256 wad);
    function file(bytes32 what, uint256 data) external;
    function fill() external returns (uint256 wad);
    function gem() external returns (address);
    function gush() external view returns (uint256 wad);
    function ilk() external returns (bytes32);
    function rush() external view returns (uint256 wad);
    function trim() external returns (uint256 wad);
    function vat() external returns (address);
}

interface GemLike {
    function decimals() external view returns (uint8);
}

interface VatLike {
    function ilks(bytes32) external view returns (uint256, uint256, uint256, uint256, uint256);
    function debt() external view returns (uint256);
    function Line() external view returns (uint256);
    function urns(bytes32, address) external view returns (uint256, uint256);
    function file(bytes32 ilk, bytes32 what, uint256 data) external;
    function file(bytes32 what, uint256 data) external;
}

contract LitePsmJobIntegrationTest is DssCronBaseTest {
    using GodMode for *;

    uint256 constant MILLION_WAD = MILLION * WAD;

    LitePsm public litePsm;
    LitePsmJob public litePsmJob;
    address public gem;
    address public dai;
    address public pocket;
    address vat;
    bytes32 ilk;

    // --- Events ---
    event Chug(uint256 wad);
    event Fill(uint256 wad);
    event Trim(uint256 wad);
    event Work(bytes32 indexed network);

    function setUpSub() internal virtual override {
        litePsm = LitePsm(dss.chainlog.getAddress("MCD_LITE_PSM_USDC_A"));
        pocket = dss.chainlog.getAddress("MCD_LITE_PSM_POCKET_USDC_A");
        dai = dss.chainlog.getAddress("MCD_DAI");
        litePsmJob =
            new LitePsmJob(address(sequencer), LitePsmLike(address(litePsm)), MILLION_WAD, MILLION_WAD, MILLION_WAD);
        gem = litePsm.gem();
        ilk = litePsm.ilk();
        vat = litePsm.vat();
        // give auth access to this contract (caller) to vat for manipulating params
        GodMode.setWard(vat, address(this), 1);
    }

    function test_fill() public {
        (uint256 Art,,, uint256 line,) = VatLike(vat).ilks(ilk);

        // tArt must be greater than Art
        // tArt = GemLike(gem).balanceOf(pocket) * gemConversionFactor + buf;
        uint256 gemConversionFactor = 10 ** (18 - GemLike(gem).decimals());
        deal(gem, pocket, Art * 2 / gemConversionFactor);

        // ilk line must be greater than Art
        uint256 newLine = Art * 2 * RAY;
        VatLike(vat).file(ilk, "line", newLine);
        (Art,,, line,) = VatLike(vat).ilks(ilk);

        // vat.Line() must be greater than vat.debt()
        uint256 vatLine = VatLike(vat).Line();
        uint256 vatDebt = VatLike(vat).debt();
        VatLike(vat).file("Line", vatLine + vatDebt);

        uint256 wad = litePsm.rush();
        assertTrue(wad != 0, "rush() returns 0");
        (bool canWork, bytes memory args) = litePsmJob.workable(NET_A);
        assertTrue(canWork, "workable returns false");
        (bytes4 fn) = abi.decode(args, (bytes4));
        assertEq(fn, litePsm.fill.selector, "fill() selector mismatch");
        vm.expectEmit(false, false, false, true);
        emit Fill(wad);
        vm.expectEmit(true, false, false, false);
        emit Work(NET_A);
        litePsmJob.work(NET_A, args);
        wad = litePsm.rush();
        assertEq(wad, 0, "rush() does not return 0");
    }

    function test_chug() public {
        // the dai balance of LitePsm must be greater than the urn's art for this ilk
        (, uint256 art) = VatLike(vat).urns(ilk, address(litePsm));
        deal(dai, address(litePsm), art + 1); //must be greater than art so we dont have underflow
        uint256 wad = litePsm.cut();
        assertTrue(wad != 0, "cut() returns 0");
        (bool canWork, bytes memory args) = litePsmJob.workable(NET_A);
        assertTrue(canWork, "workable returns false");
        (bytes4 fn) = abi.decode(args, (bytes4));
        assertEq(fn, litePsm.chug.selector, "chug() selector mismatch");
        vm.expectEmit(false, false, false, true);
        emit Chug(wad);
        vm.expectEmit(true, false, false, false);
        emit Work(NET_A);
        litePsmJob.work(NET_A, args);
        wad = litePsm.cut();
        assertEq(wad, 0, "cut() does not return 0");
    }

    function test_trim() public {
        (uint256 Art,,, uint256 line,) = VatLike(vat).ilks(ilk);
        // Art must be greater than ilk line
        uint256 newLine = (Art / 2) * RAY;
        VatLike(vat).file(ilk, "line", newLine);
        (Art,,, line,) = VatLike(vat).ilks(ilk);
        // dai balance of LitePsm must be non-zero
        deal(dai, address(litePsm), Art);
        // workable() will return chug() because it has precedence!
        (bool canWork, bytes memory args) = litePsmJob.workable(NET_A);
        assertTrue(canWork, "workable returns false");
        (bytes4 fn) = abi.decode(args, (bytes4));
        assertEq(fn, litePsm.chug.selector, "chug() selector mismatch");
        // call chug() first!
        litePsmJob.work(NET_A, args);
        // gush() should return a non zero value so trim() meaning that trim can be called
        uint256 wad = litePsm.gush();
        assertTrue(wad != 0, "gush() returns 0");
        // we call workable again, it should return trim() now!
        (canWork, args) = litePsmJob.workable(NET_A);
        assertTrue(canWork, "workable returns false");
        (fn) = abi.decode(args, (bytes4));
        assertEq(fn, litePsm.trim.selector, "trim() selector mismatch");
        vm.expectEmit(false, false, false, true);
        emit Trim(wad);
        vm.expectEmit(true, false, false, false);
        emit Work(NET_A);
        litePsmJob.work(NET_A, args);
        wad = litePsm.gush();
        assertEq(wad, 0, "gush() does not return 0");
    }

    /**
     *  Revert Test Cases **
     */
    function test_noWork() public {
        (bool canWork, bytes memory args) = litePsmJob.workable(NET_A);
        assertTrue(canWork == false, "workable() returns true");
        assertEq(args, bytes("No work to do"), "Wrong No work  message");
    }

    function test_unsupportedFunction() public {
        bytes4 fn = 0x00000000;
        bytes memory args = abi.encode(fn);
        vm.expectRevert(abi.encodeWithSelector(LitePsmJob.UnsupportedFunction.selector, fn));
        litePsmJob.work(NET_A, args);
    }

    function test_nonMasterNetwork() public {
        bytes32 network = "ERROR";
        bytes memory args = abi.encode("0");
        vm.expectRevert(abi.encodeWithSelector(LitePsmJob.NotMaster.selector, network));
        litePsmJob.work(network, args);
    }
}
