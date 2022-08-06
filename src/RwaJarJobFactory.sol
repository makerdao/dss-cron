// SPDX-FileCopyrightText: © 2022 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {TimedJob} from "./base/TimedJob.sol";

import {ScheduledJarVoidJob} from "./ScheduledJarVoidJob.sol";

import "./utils/EnumerableSet.sol";


/**
 * @dev interface for the RWARegistry
 */
interface RWARegistryLike {
    enum DealStatus {
        NONE, // The deal does not exist.
        ACTIVE, // The deal is active.
        FINALIZED // The deal was finalized.
    }
 
    function ilkToDeal(bytes32 ilk) external view returns (DealStatus, uint248);
    function list() external view returns (bytes32[] memory);
    function count() external view returns (uint256);
    function getComponent(bytes32 ilk_, bytes32 name_) external view returns (address addr, uint88 variant);
}


/**
 * @title RWA Job Factory
 * @author David Krett <david@w2d.co>
 * @notice Scans the RWA Registry for Urn and Jar jobs and creates jobs if they dont exist
 */
contract RwaJarJobFactory is TimedJob {
    
    using EnumerableSet for EnumerableSet.AddressSet;
        
    EnumerableSet.AddressSet private jobs;

    enum DealStatus {
        NONE, // The deal does not exist.
        ACTIVE, // The deal is active.
        FINALIZED // The deal was finalized.
    }

    RWARegistryLike public immutable rwaRegistry;

    mapping(bytes32 => address) public jarJobs;

    bytes32 constant public COMPONENT = "jar";

    /**
    * @notice The jar job identified by `ilk` was added to the jobs network.
    * @param jar The jar address.
    */
    event CreateJarJob(address indexed jar);

    /**
    * @notice The jar job identified by `ilk` was removed from the jobs network.
    * @param jar The jar address.
    */
    event RemoveJarJob(address indexed jar);

    constructor(address _sequencer, address _rwaRegistry, uint256 _duration) TimedJob(_sequencer, _duration) {
        rwaRegistry = RWARegistryLike(_rwaRegistry);
    }

    /**
    * @notice checks the RWA registry for new or redundant jar jobs.
    * @param .
    */
    function shouldUpdate() internal override view returns (bool) {
        // If any of these returns true an update is needed.
        if (_checkJarsWithoutJobs() == true) {
            return true;
        }
        if (_checkActiveJobsForInactiveDeals() == true) {
            return true;
        }
        // Note Edge case check for changed deals
        return false;
    }

    /**
    * @notice checks the RWA registry for new or redundant jar jobs.
    */
    function update() internal override {
        // store the last index of registy jobs 
        // add in new and remove any inactive jobs
        // create jobs for new jars
        _checkForNewJarJobs();
        _checkForTerminatedJobs();

    }

    /**
     * @notice iterates over RwaRegistry and returns true if jobs need to be deployed
     */
    function _checkJarsWithoutJobs() internal view returns (bool) {
        bytes32[] memory ilks = rwaRegistry.list();
        for (uint256 i = 0; i < ilks.length; i++) {
            try rwaRegistry.ilkToDeal(ilks[i]) returns (RWARegistryLike.DealStatus status, uint248) {
            if (status == RWARegistryLike.DealStatus.ACTIVE) {
                try rwaRegistry.getComponent(ilks[i], COMPONENT) returns (address addr, uint88) {
                    if (addr != address(0) && jarJobs[ilks[i]] == address(0)) {
                        return true;
                    }
                } catch {
                    continue;
                }
            }

            }
            catch {
                continue;
            }
        }
        return false;
    }

    function _checkForNewJarJobs() internal {
        bytes32[] memory ilks = rwaRegistry.list();
        for (uint256 i = 0; i < ilks.length; i++) {
            try rwaRegistry.ilkToDeal(ilks[i]) returns (RWARegistryLike.DealStatus status, uint248) {
            if (status == RWARegistryLike.DealStatus.ACTIVE) {
                try rwaRegistry.getComponent(ilks[i], COMPONENT) returns (address addr, uint88) {
                    if (addr != address(0) && !jobs.contains(jarJobs[ilks[i]])) {
                        address jarJob = _createJarJob(addr);
                        jobs.add(jarJob);
                        jarJobs[ilks[i]] = jarJob;
                        emit CreateJarJob(addr);
                    }
                } catch {
                    continue;
                }
            }

            }
            catch {
                continue;
            }
        }

    }

    function _createJarJob(address jar) internal returns (address){
        ScheduledJarVoidJob jarJob = new ScheduledJarVoidJob(address(sequencer), jar, 15 days);
        sequencer.addJob(address(jarJob));
        return address(jarJob);
    }

    /**
     * @notice iterates over RwaRegistry and returns true if jobs need to be removed
     */
    function _checkActiveJobsForInactiveDeals() internal view returns (bool) {
        bytes32[] memory ilks = rwaRegistry.list();

        for (uint i = 0; i < ilks.length; i++) {
            if (jarJobs[ilks[i]] != address(0)) {
                try rwaRegistry.ilkToDeal(ilks[i]) returns (RWARegistryLike.DealStatus status, uint248) {
                    if (status != RWARegistryLike.DealStatus.ACTIVE) {
                        return true;
                    }
                } catch {
                    continue;
                }
            }
        }
        return false;
    }

    function _checkForTerminatedJobs() internal {
        bytes32[] memory ilks = rwaRegistry.list();
        for (uint i = 0; i < ilks.length; i++) {
            if (jarJobs[ilks[i]] != address(0)) {
                try rwaRegistry.ilkToDeal(ilks[i]) returns (RWARegistryLike.DealStatus status, uint248) {
                    if (status != RWARegistryLike.DealStatus.ACTIVE) {
                        (address addr, ) = rwaRegistry.getComponent(ilks[i], COMPONENT);
                        sequencer.removeJob(jarJobs[ilks[i]]);
                        jobs.remove(address(jarJobs[ilks[i]]));
                        jarJobs[ilks[i]] = address(0);
                        emit RemoveJarJob(addr);
                    }
                } catch {
                    continue;
                }
            }
        }
    }
}