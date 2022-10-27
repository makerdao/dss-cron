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

import {ChainlogAbstract} from "dss-interfaces/dss/ChainlogAbstract.sol";
import {DaiAbstract} from "dss-interfaces/dss/DaiAbstract.sol";

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

    function ilkToDeal(bytes32 ilk) external view returns (DealStatus status, uint256 pos);
    function list() external view returns (bytes32[] memory);
    function getComponent(bytes32 ilk, bytes32 name) external view returns (address addr, uint88 variant);
}

interface RwaJarLike {
    function void() external;
}

interface RwaUrnLike {
    function wipe(uint256 wad) external;
}

/**
 * @title Trigger void of RWA Jars that have a minimum balance threshold
 * @author David Krett <
 */
contract RwaJob is IJob {
    SequencerLike public immutable sequencer;
    RWARegistryLike public immutable rwaRegistry;
    DaiAbstract public immutable dai;
    uint256 public immutable threshold;

    bytes32 constant internal URN_COMPONENT = "urn";
    bytes32 constant internal JAR_COMPONENT = "jar";

    // --- Errors ---
    error NotMaster(bytes32 network);
    error DealNotActive(bytes32 ilk);
    error BalanceBelowThreshold(bytes32 ilk, bytes32 componentName, uint256 balance);
    error InvalidComponent(bytes32 ilk, bytes32 componentName);

    // --- Events ---
    event Work(bytes32 indexed network, bytes32 indexed ilk, bytes32 indexed componentName);

    constructor(address _sequencer, address _rwaRegistry, address _dai, uint256 _threshold) {
        sequencer = SequencerLike(_sequencer);
        rwaRegistry = RWARegistryLike(_rwaRegistry);
        threshold = _threshold;
        dai = DaiAbstract(_dai);
    }

    function work(bytes32 network, bytes calldata args) external override {
        if (!sequencer.isMaster(network)) revert NotMaster(network);

        (bytes32 ilk, bytes32 componentName) = abi.decode(args, (bytes32, bytes32));

        (RWARegistryLike.DealStatus status,) = rwaRegistry.ilkToDeal(ilk);

        // If the deal is not active, skip it.
        if (status != RWARegistryLike.DealStatus.ACTIVE) {
            revert DealNotActive(ilk);
        }

        (address addr, uint88 variant) = rwaRegistry.getComponent(ilk, componentName);

        if (componentName == JAR_COMPONENT) {
            executeJarActions(ilk, addr, variant);
        } else if(componentName == URN_COMPONENT) {
            executeUrnActions(ilk, addr, variant);
        } else {
            revert InvalidComponent(ilk, componentName);
        }

        emit Work(network, ilk, componentName);
    }

    function executeJarActions(bytes32 ilk, address jar, uint88) internal {
        // If its balance is below the threshold, skip it.
        if (dai.balanceOf(jar) < threshold) {
            revert BalanceBelowThreshold(ilk, JAR_COMPONENT, dai.balanceOf(jar));
        }

        RwaJarLike(jar).void();
    }

    function executeUrnActions(bytes32 ilk, address urn, uint88) internal {
        // If its balance is below the threshold, skip it.
        if (dai.balanceOf(urn) < threshold) {
            revert BalanceBelowThreshold(ilk, URN_COMPONENT, dai.balanceOf(urn));
        }

        RwaUrnLike(urn).wipe(dai.balanceOf(urn));
    }

    function workable(bytes32 network) external view override returns (bool, bytes memory) {
        if (!sequencer.isMaster(network)) return (false, bytes("Network is not master"));

        bytes32[] memory ilks = rwaRegistry.list();

        for (uint256 i = 0; i < ilks.length; i++) {
            bytes32 ilk = ilks[i];

            (RWARegistryLike.DealStatus status,) = rwaRegistry.ilkToDeal(ilk);
            if (status == RWARegistryLike.DealStatus.ACTIVE) {
                // We check if there is a jar for the ilk with balance above the predefined threshold.
                try rwaRegistry.getComponent(ilk, JAR_COMPONENT) returns (address jar, uint88) {
                    if (dai.balanceOf(jar) >= threshold) {
                        return (true, abi.encode(ilk, JAR_COMPONENT));
                    }
                } catch {}

                // Otherwise, we check for a unr for the ilk with balance above the predefined threshold.
                try rwaRegistry.getComponent(ilk, URN_COMPONENT) returns (address urn, uint88) {
                    if (dai.balanceOf(urn) >= threshold) {
                        return (true, abi.encode(ilk, URN_COMPONENT));
                    }
                } catch {}
            }
        }
        return (false, bytes("No RWA jobs"));
    }
}
