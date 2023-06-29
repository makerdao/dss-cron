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

import {IJob} from "./interfaces/IJob.sol";

interface SequencerLike {
    function isMaster(bytes32 network) external view returns (bool);
}

interface VatLike {
    function sin(address) external view returns (uint256);
}

interface VowLike {
    function flapper() external view returns (address);
    function Sin() external view returns (uint256);
    function Ash() external view returns (uint256);
    function heal(uint256) external;
    function flap() external;
}

interface FlapperLike {
    function zzz() external view returns (uint256);
    function hop() external view returns (uint256);
}

/// @title Call flap when possible
contract FlapJob is IJob {

    SequencerLike public immutable sequencer;
    VatLike       public immutable vat;
    VowLike       public immutable vow;
    FlapperLike   public immutable flapper;
    uint256       public immutable maxGasPrice;
    uint256       public immutable delay;

    // --- Errors ---
    error NotMaster(bytes32 network);
    error GasPriceTooHigh(uint256 gasPrice, uint256 maxGasPrice);
    error TooEarly();

    // --- Events ---
    event Work(bytes32 indexed network);

    constructor(address _sequencer, address _vat, address _vow, uint256 _maxGasPrice, uint256 _delay) {
        sequencer   = SequencerLike(_sequencer);
        vat         = VatLike(_vat);
        vow         = VowLike(_vow);
        flapper     = FlapperLike(vow.flapper());
        maxGasPrice = _maxGasPrice;
        delay       = _delay;
    }

    function work(bytes32 network, bytes calldata args) public {
        if (!sequencer.isMaster(network)) revert NotMaster(network);
        if (tx.gasprice > maxGasPrice)    revert GasPriceTooHigh(tx.gasprice, maxGasPrice);
        if (block.timestamp < flapper.zzz() + flapper.hop() + delay) revert TooEarly();

        uint256 toHeal = abi.decode(args, (uint256));
        if (toHeal > 0) vow.heal(toHeal);
        vow.flap();

        emit Work(network);
    }

    function workable(bytes32 network) external override returns (bool, bytes memory) {
        if (!sequencer.isMaster(network)) return (false, bytes("Network is not master"));

        bytes memory args;
        uint256 unbackedTotal = vat.sin(address(vow));
        uint256 unbackedVow   = vow.Sin() + vow.Ash();

        // Check if need to cancel out free unbacked debt with system surplus
        uint256 toHeal = unbackedTotal > unbackedVow ? unbackedTotal - unbackedVow : 0;
        args = abi.encode(toHeal);

        try this.work(network, args) {
            // Flap succeeds
            return (true, args);
        } catch {
            // Can not flap -- carry on
        }
        return (false, bytes("Flap not possible"));
    }
}
