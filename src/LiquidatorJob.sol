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
pragma solidity ^0.8.9;

import "./IJob.sol";

interface SequencerLike {
    function isMaster(bytes32 network) external view returns (bool);
}

interface IlkRegistryLike {
    function list() external view returns (bytes32[] memory);
    function xlip() external view returns (address);
    function info(bytes32 ilk) external view returns (
        string memory name,
        string memory symbol,
        uint256 class,
        uint256 dec,
        address gem,
        address pip,
        address join,
        address xlip
    );
}

interface ClipLike {
    function list() external view returns (uint256[] memory);
    function take(
        uint256 id,           // Auction id
        uint256 amt,          // Upper limit on amount of collateral to buy  [wad]
        uint256 max,          // Maximum acceptable price (DAI / collateral) [ray]
        address who,          // Receiver of collateral and external call address
        bytes calldata data   // Data to pass in external call; if length 0, no call is done
    ) external;
}

interface VatLike {
    function ilks(bytes32) external view returns (uint256, uint256, uint256, uint256, uint256);
}

// Provide backstop liquidations across all supported DEXs
contract LiquidatorJob is IJob {

    uint256 constant internal BPS = 10 ** 4;
    
    SequencerLike public immutable sequencer;
    IlkRegistryLike public immutable ilkRegistry;
    VatLike public immutable vat;
    address public immutable profit;
    address[] public exchangeCallees;

    constructor(address _sequencer, address _ilkRegistry, address _target, address[] memory _exchangeCallees) {
        sequencer = SequencerLike(_sequencer);
        ilkRegistry = IlkRegistryLike(_ilkRegistry);
        target = _target;       // use dss-blow 0x0048FC4357DB3c0f45AdEA433a07A20769dDB0CF
        exchangeCallees = _exchangeCallees;
    }

    function getNextJob(bytes32 network) external override returns (bool, address, bytes memory) {
        if (!sequencer.isMaster(network)) return (false, address(0), bytes("Network is not master"));
        
        bytes32[] memory ilks = ilkRegistry.list();
        for (uint256 i = 0; i < ilks.length; i++) {
            bytes32 ilk = ilks[i];
            (,, uint256 class,,,,,) = ilkRegistry.info(ilk);
            if (class != 1) continue;

            ClipLike clip = ClipLike(ilkRegistry.xlip());
            if (address(clip) == address(0)) continue;
            
            uint256[] memory auctions = clip.list();
            for (uint256 o = 0; o < auctions.length; o++) {
                uint256 auction = auctions[o];

                for (uint256 p = 0; p < exchangeCallees.length; p++) {
                    address exchangeCallee = exchangeCallees[p];

                    bytes memory data = abi.encode(
                        profit,
                        
                    );

                    try clip.take(auction, type(uint256).max, type(uint256).max, exchangeCallee) {
                        // Found an auction!
                        return (true, address(clip), abi.encodeWithSelector(ClipLike.take.selector, auction, type(uint256).max, type(uint256).max, exchangeCallee));
                    } catch {
                        // No valid auction -- carry on
                    }
                }
            }
        }

        return (false, address(0), bytes("No auctions"));
    }

}
