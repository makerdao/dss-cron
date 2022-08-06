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
import {RwaUrnWipeJob} from "../RwaUrnWipeJob.sol";

/**
 * @dev interface for the RWARegistry
 */
interface RWARegistryLike {
    enum DealStatus {
        NONE, // The deal does not exist.
        ACTIVE, // The deal is active.
        FINALIZED // The deal was finalized.
    }

    function ilkToDeal(bytes32 ilk) external view returns (DealStatus);
    function list() external view returns (bytes32[] memory);
    function getComponent(bytes32 ilk_, bytes32 name_) external view returns (address addr);
    function finalize(bytes32 ilk_) external;
}

contract RwaUrnVoidTest is DssCronBaseTest {
    using GodMode for *;
    using stdStorage for StdStorage;

    RwaUrnWipeJob public rwaUrnWipeJob;

    bytes32 internal constant RWA009 = "RWA009-A";
    bytes32 internal constant URN = "urn";
    uint256 testDaiAmount = 10_000 * WAD;

    address internal registryAddr;

    event Wipe(address indexed usr, uint256 wad);
    event Work(bytes32 indexed network, bytes32 indexed ilk);

    function setUpSub() virtual override internal {
        registryAddr = vm.envAddress("MIP21_REGISTRY");
        // registryAddr = mcd.chainlog().getAddress("MIP21_REGISTRY");
        
        rwaUrnWipeJob = new RwaUrnWipeJob(
            address(sequencer),
            address(registryAddr),
            address(mcd.chainlog().getAddress("MCD_DAI")),
            500 * WAD
        );

        sequencer.rely(address(rwaUrnWipeJob));

        // Clear out all existing jobs by moving ahead 1 years
        GodMode.vm().warp(block.timestamp + 365 days * 1);
    }

    function testRwaUrnWipeJobEmptiesUrn() public {
        // RWA009 is our test jar - lets set the jar balance to 0
        (address urn)   = RWARegistryLike(registryAddr).getComponent(RWA009, URN);
        deal(address(mcd.dai()), urn, 0, true);
    
        assertEq(mcd.dai().balanceOf(urn), 0);

        (bool canWork, bytes memory args) = rwaUrnWipeJob.workable(NET_A);  
        assertTrue(!canWork, "Should not work as 0 balance and threshold is 500");
        
        // Add a balance greater than the threshold and the job should work
        deal(address(mcd.dai()), urn, testDaiAmount, true);
        assertEq(mcd.dai().balanceOf(urn), testDaiAmount);

        
        // Check that the job can work
        uint256 daiSupplyBefore = mcd.dai().totalSupply();

        (canWork, args) = rwaUrnWipeJob.workable(NET_A);
        assertTrue(canWork, "Should be able to work as balance is greater than threshold");
        bytes32 actualArgs = bytes32(args);
        assertEq(actualArgs, RWA009);


        // Running the job should wipe the urn and burn the dai

        // Check that the correct events are emitted
        vm.expectEmit(true, true, false, false);
        emit Wipe(address(rwaUrnWipeJob), testDaiAmount);

        vm.expectEmit(true, true, false, false);
        emit Work(NET_A, RWA009);

        rwaUrnWipeJob.work(NET_A, args);

        uint256 daiSupplyAfter = mcd.dai().totalSupply();
        uint256 expectedDaiSupply = daiSupplyBefore - testDaiAmount;

        assertEq(mcd.dai().balanceOf(address(urn)), 0, "Balance of RwaUrn is not zero");
        assertEq(daiSupplyAfter, expectedDaiSupply, "Total supply of Dai did not change after burn");
 
    }

    function testRwaUrnWipeJobReverts() public {
        (address urn) = RWARegistryLike(registryAddr).getComponent(RWA009, URN);
        deal(address(mcd.dai()), urn, 0, true);

        // If work is called balance will revert when balance below threshold

        vm.expectRevert(
            abi.encodeWithSelector(
                RwaUrnWipeJob.BalanceBelowThreshold.selector, 
                0,
                rwaUrnWipeJob.threshold()
            )
        );

        rwaUrnWipeJob.work(NET_A, abi.encode(RWA009));

        // If rwa registry deal is finalized it will revert 

        _setWardsRwaRegistry();
        RWARegistryLike(registryAddr).finalize(RWA009); 

        vm.expectRevert(
            abi.encodeWithSelector(RwaUrnWipeJob.DealNotActive.selector, RWA009)
        );

        rwaUrnWipeJob.work(NET_A, abi.encode(RWA009));

    }

    function _setWardsRwaRegistry() internal  {
        stdstore
            .target(registryAddr)
            .sig("wards(address)")
            .with_key(address(this))
            .checked_write(1);
    }
}


