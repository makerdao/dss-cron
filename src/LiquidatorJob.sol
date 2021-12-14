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

interface VatLike {
    function can(address, address) external view returns (uint256);
    function hope(address) external;
    function dai(address) external view returns (uint256);
    function move(address, address, uint256) external;
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
}

interface ILiquidatorJob {
    function execute(address target, bytes calldata data) external;
}

// Provide backstop liquidations across all supported DEXs
contract LiquidatorJob is IJob {

    uint256 constant internal BPS = 10 ** 4;
    
    SequencerLike public immutable sequencer;
    VatLike public immutable vat;
    DaiJoinLike public immutable daiJoin;
    DaiLike public immutable dai;
    IlkRegistryLike public immutable ilkRegistry;
    address public immutable profitTarget;

    address public immutable uniswapV3Callee;

    constructor(address _sequencer, address _daiJoin, address _ilkRegistry, address _profitTarget, address _uniswapV3Callee) {
        sequencer = SequencerLike(_sequencer);
        daiJoin = DaiJoinLike(_daiJoin);
        vat = VatLike(daiJoin.vat());
        dai = DaiLike(daiJoin.dai());
        ilkRegistry = IlkRegistryLike(_ilkRegistry);
        profitTarget = _profitTarget;
        uniswapV3Callee = _uniswapV3Callee;

        dai.approve(_daiJoin, type(uint256).max);
    }

    // Warning! This contract can execute arbitrary code. Never give authorizations to anything.
    function execute(address target, bytes calldata data) public {
        if (vat.can(address(this), target) != 1) {
            vat.hope(target);
        }
        (bool success,) = target.call(data);
        require(success, "call failed");

        // Dump all extra DAI into the profit target
        daiJoin.join(address(this), dai.balanceOf(address(this)));
        vat.move(address(this), profitTarget, vat.dai(address(this)));
    }

    function getNextJob(bytes32 network) external override returns (bool, address, bytes memory) {
        if (!sequencer.isMaster(network)) return (false, address(0), bytes("Network is not master"));
        
        bytes32[] memory ilks = ilkRegistry.list();
        for (uint256 i = 0; i < ilks.length; i++) {
            bytes32 ilk = ilks[i];
            (,, uint256 class,, address gem,, address join, address _clip) = ilkRegistry.info(ilk);
            if (class != 1) continue;
            ClipLike clip = ClipLike(_clip);
            if (address(clip) == address(0)) continue;
            
            uint256[] memory auctions = clip.list();
            for (uint256 o = 0; o < auctions.length; o++) {
                uint256 auction = auctions[o];

                // Attempt to run this through Uniswap V3 first
                {
                    bytes memory data = abi.encodeWithSelector(
                        ClipLike.take.selector,
                        auction,
                        type(uint256).max,
                        type(uint256).max,
                        uniswapV3Callee,
                        abi.encode(
                            address(this),
                            join,
                            0,
                            abi.encodePacked(gem, uint24(500), dai),
                            address(0)
                        )
                    );

                    try this.execute(address(clip), data) {
                        // Found an auction!
                        return (true, address(this), abi.encodeWithSelector(
                            ILiquidatorJob.execute.selector,
                            address(clip),
                            data
                        ));
                    } catch {
                        // No valid auction -- carry on
                    }
                }
            }
        }

        return (false, address(0), bytes("No auctions"));
    }

}
