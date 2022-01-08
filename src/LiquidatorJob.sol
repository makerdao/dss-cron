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
pragma solidity 0.8.9;

import {IJob} from "./interfaces/IJob.sol";

interface SequencerLike {
    function isMaster(bytes32 network) external view returns (bool);
}

interface VatLike {
    function can(address, address) external view returns (uint256);
    function hope(address) external;
    function dai(address) external view returns (uint256);
    function move(address, address, uint256) external;
    function wards(address) external view returns (uint256);
}

interface DaiJoinLike {
    function vat() external view returns (address);
    function dai() external view returns (address);
    function join(address, uint256) external;
}

interface DaiLike {
    function approve(address, uint256) external returns (bool);
    function balanceOf(address) external view returns (uint256);
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
    function sales(uint256) external view returns (uint256,uint256,uint256,address,uint96,uint256);
}

// Provide backstop liquidations across all supported DEXs
contract LiquidatorJob is IJob {

    uint256 constant internal BPS = 10 ** 4;
    uint256 constant internal RAY = 10 ** 27;
    
    SequencerLike public immutable sequencer;
    VatLike public immutable vat;
    DaiJoinLike public immutable daiJoin;
    DaiLike public immutable dai;
    IlkRegistryLike public immutable ilkRegistry;
    address public immutable profitTarget;

    address public immutable uniswapV3Callee;
    uint256 public immutable minProfitBPS;          // Profit as % of debt owed

    // --- Errors ---
    error NotMaster(bytes32 network);
    error InvalidClipper(address clip);

    constructor(address _sequencer, address _daiJoin, address _ilkRegistry, address _profitTarget, address _uniswapV3Callee, uint256 _minProfitBPS) {
        sequencer = SequencerLike(_sequencer);
        daiJoin = DaiJoinLike(_daiJoin);
        vat = VatLike(daiJoin.vat());
        dai = DaiLike(daiJoin.dai());
        ilkRegistry = IlkRegistryLike(_ilkRegistry);
        profitTarget = _profitTarget;
        uniswapV3Callee = _uniswapV3Callee;
        minProfitBPS = _minProfitBPS;

        dai.approve(_daiJoin, type(uint256).max);
    }

    function work(bytes32 network, bytes calldata args) public {
        if (!sequencer.isMaster(network)) revert NotMaster(network);
        
        (address clip, uint256 auction, bytes memory calleePayload) = abi.decode(args, (address, uint256, bytes));
        
        // Verify clipper is a valid contract
        // Easiest way to do this is check it's authed on the vat
        if (vat.wards(clip) != 1) revert InvalidClipper(clip);

        if (vat.can(address(this), clip) != 1) {
            vat.hope(clip);
        }
        ClipLike(clip).take(
            auction,
            type(uint256).max,
            type(uint256).max,
            uniswapV3Callee,
            calleePayload
        );

        // Dump all extra DAI into the profit target
        daiJoin.join(address(this), dai.balanceOf(address(this)));
        vat.move(address(this), profitTarget, vat.dai(address(this)));
    }

    function workable(bytes32 network) external override returns (bool, bytes memory) {
        if (!sequencer.isMaster(network)) return (false, bytes("Network is not master"));
        
        bytes32[] memory ilks = ilkRegistry.list();
        for (uint256 i = 0; i < ilks.length; i++) {
            (,, uint256 class,, address gem,, address join, address clip) = ilkRegistry.info(ilks[i]);
            if (class != 1) continue;
            if (clip == address(0)) continue;
            
            uint256[] memory auctions = ClipLike(clip).list();
            for (uint256 o = 0; o < auctions.length; o++) {
                // Attempt to run this through Uniswap V3 liquidator
                uint24[2] memory fees = [uint24(500), uint24(3000)];
                for (uint256 p = 0; p < fees.length; p++) {
                    bytes memory args;
                    {
                        // Stack too deep
                        (, uint256 tab,,,,) = ClipLike(clip).sales(auctions[o]);
                        bytes memory calleePayload = abi.encode(
                            address(this),
                            join,
                            tab * minProfitBPS / BPS / RAY,
                            abi.encodePacked(gem, fees[p], dai),
                            address(0)
                        );
                        args = abi.encode(
                            clip,
                            auctions[o],
                            calleePayload
                        );
                    }

                    try this.work(network, args) {
                        // Found an auction!
                        return (true, args);
                    } catch {
                        // No valid auction -- carry on
                    }
                }
            }
        }

        return (false, bytes("No auctions"));
    }

}
