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

import {DaiAbstract} from "dss-interfaces/dss/DaiAbstract.sol";
import {ChainlogAbstract} from "dss-interfaces/dss/ChainlogAbstract.sol";

import {IJob} from "./interfaces/IJob.sol";

interface SequencerLike {
    function isMaster(bytes32 network) external view returns (bool);
}

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
    function getComponent(bytes32 ilk, bytes32 name) external view returns (address addr, uint88 variant);
}

interface RwaUrnLike {
    function wipe(uint256) external;
}

/**
 * @author David Krett <david@w2d.co>
 * @title ScheduledUrnWipeJob
 * @dev checks the balance in a urn and if above a threshold balance voids the urn
 */

contract RwaUrnWipeJob is IJob {
    bytes32 constant internal COMPONENT = "urn";

    SequencerLike public immutable sequencer;
    RWARegistryLike public immutable rwaRegistry;
    DaiAbstract public immutable dai;
    uint256 public immutable threshold;

    // --- Errors ---
    error NotMaster(bytes32 network);
    error DealNotActive(bytes32 ilk);
    error UnexistingComponent(bytes32 ilk);
    error BalanceBelowThreshold(bytes32 ilk, uint256 balance);

    // --- Events ---
    event Work(bytes32 indexed network, bytes32 indexed ilk);

    constructor(address _sequencer, address _rwaRegistry, address _dai, uint256 _threshHold) {
        sequencer = SequencerLike(_sequencer);
        rwaRegistry = RWARegistryLike(_rwaRegistry);
        threshold = _threshHold;
        dai = DaiAbstract(_dai);
    }

    function work(bytes32 network, bytes calldata args) external override {
        if (!sequencer.isMaster(network)) revert NotMaster(network);

        bytes32 ilk = abi.decode(args, (bytes32));

        RWARegistryLike.DealStatus status = rwaRegistry.ilkToDeal(ilk);

        // If the deal is not active, skip it.
        if (status != RWARegistryLike.DealStatus.ACTIVE) {
            revert DealNotActive(ilk);
        }

        (address urn, ) = rwaRegistry.getComponent(ilk, COMPONENT);

        // If the component is invalid, skip it.
        if (urn == address(0)) {
            revert UnexistingComponent(ilk);
        }

        // If its balance is below the threshold, skip it.
        if (dai.balanceOf(urn) < threshold) {
            revert BalanceBelowThreshold(ilk, dai.balanceOf(urn));
        }

        RwaUrnLike(urn).wipe(dai.balanceOf(urn));

        emit Work(network, ilk);
    }

    function workable(bytes32 network) external view override returns (bool, bytes memory) {
        if (!sequencer.isMaster(network)) return (false, bytes("Network is not master"));

        bytes32[] memory ilks = rwaRegistry.list();

        for (uint256 i = 0; i < ilks.length; i++) {
            bytes32 ilk = ilks[i];

            // We check if the jar for the ilk if above the predefined threshold.
            RWARegistryLike.DealStatus status = rwaRegistry.ilkToDeal(ilk);
            if (status == RWARegistryLike.DealStatus.ACTIVE) {
                try rwaRegistry.getComponent(ilk, COMPONENT) returns (address addr, uint88) {
                    if (addr != address(0)) {
                        if (dai.balanceOf(addr) >= threshold) {
                            return (true, abi.encode(ilk));
                        }
                    }
                } catch {}
            }
        }
        return (false, bytes("No urns above threshold"));
    }
}
