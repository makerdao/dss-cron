// SPDX-FileCopyrightText: © 2022 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {TimedJob} from "./base/TimedJob.sol";

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
    
    RWARegistryLike public immutable rwaRegistry;

    mapping(bytes32 => address) public jarJobs;

    constructor(address _sequencer, address _rwaRegistry, uint256 _duration) TimedJob(_sequencer, _duration) {
        rwaRegistry = RWARegistryLike(_rwaRegistry);
    }

  /**
   * @notice checks the RWA registry for new or redundant jar jobs.
   * @param .
   */
    function shouldUpdate() internal override view returns (bool) {
      // Check the registry for urns and jars
      // Check if there are jobs for the identifed urns and jar/// @notice Explain to an end user what this does
      /// @dev Explain to a developer any extra details
      /// @return Documents the return variables of a contract’s function state variable
      /// @inheritdoc	Copies all missing tags from the base function (must be followed by the contract name)
        return rwaRegistry.count() > 0;
    }

  /**
   * @notice checks the RWA registry for new or redundant jar jobs.
   */
    function update() internal override {}
}