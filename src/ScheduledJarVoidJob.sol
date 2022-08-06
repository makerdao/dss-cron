// SPDX-FileCopyrightText: © 2022 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {TimedJob} from "./base/TimedJob.sol";

interface RwaJarLike {
    function daiJoin() external returns(address);
    function dai() external returns(address);
    function chainlog() external returns(address);
    function void() external;
    function toss(uint256) external;
}


/**
 * @title ScheduledJarVoidJob
 * @author David Krett <david@w2d.co>
 * @notice checks the balance in a Jar and if above a threshold balance voids the jar
 */
contract ScheduledJarVoidJob is TimedJob {
    
    RwaJarLike public immutable rwaJar;




    constructor(address _sequencer, address _jar, uint256 _duration) TimedJob(_sequencer, _duration) {
        rwaJar = RwaJarLike(_jar);
    }

    /**
    * @notice checks the designated jar balance and indicates whether it needs to be voided.
    * @param .
    */
    function shouldUpdate() internal override view returns (bool) {
       // check for a threshold balance in the jar and if above will return true
        // Check the registry for jars without jobs
        // bytes32[] memory ilks = rwaRegistry.list();
        // for (uint256 i = 0; i < ilks.length; i++) {
        //     (RWARegistryLike.DealStatus status, uint248 pos) = rwaRegistry.ilkToDeal(ilks[i]);
        //     if (status == RWARegistryLike.DealStatus.ACTIVE) {
        //         (address addr, uint88 variant) = rwaRegistry.getComponent(ilks[i], component);
        //         if (addr != address(0) && jarJobs[ilks[i]] == address(0)) {
        //             return true;
        //         }
        //     }
        // }
        return true;
    }

  /**
   * @notice voids the designated Jar.
   */
    function update() internal override {
      // call void function on the jar 
    }
}