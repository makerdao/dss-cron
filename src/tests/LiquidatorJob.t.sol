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

import "./DssCronBase.t.sol";
import {LiquidatorJob} from "../LiquidatorJob.sol";

interface JugLike {
    function drip(bytes32) external returns (uint256);
}

interface DogLike {
    function bark(bytes32,address,address) external returns (uint256);
}

interface ClipLike {
    function kicks() external view returns (uint256);
    function active(uint256) external view returns (uint256);
    function sales(uint256) external view returns (uint256,uint256,uint256,address,uint96,uint256);
    function kick(uint256,uint256,address,address) external returns (uint256);
    function redo(uint256,address) external;
    function take(uint256,uint256,uint256,address,bytes calldata) external;
    function count() external view returns (uint256);
    function list() external view returns (uint256[] memory);
}

contract LiquidatorTest is DssCronBaseTest {

    TokenLike weth;
    JoinLike wethJoin;
    ClipLike wethClip;
    JugLike jug;
    DogLike dog;
    address uniswapV3Callee;

    LiquidatorJob liquidatorJob;
    LiquidatorJob liquidatorJob500;

    function setUpSub() virtual override internal {
        weth = TokenLike(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        wethJoin = JoinLike(0x2F0b23f53734252Bda2277357e97e1517d6B042A);
        wethClip = ClipLike(0xc67963a226eddd77B91aD8c421630A1b0AdFF270);
        jug = JugLike(0x19c0976f590D67707E62397C87829d896Dc0f1F1);
        dog = DogLike(0x135954d155898D42C90D2a57824C690e0c7BEf1B);
        uniswapV3Callee = 0xdB9C76109d102d2A1E645dCa3a7E671EBfd8e11A;

        // 0% profit expectation
        liquidatorJob = new LiquidatorJob(address(sequencer), address(daiJoin), address(ilkRegistry), vow, uniswapV3Callee, 0);

        // 5% profit expectation
        liquidatorJob500 = new LiquidatorJob(address(sequencer), address(daiJoin), address(ilkRegistry), vow, uniswapV3Callee, 500);

        // TODO clear out any existing auctions

        // Create an auction on ETH-A
        uint256 wethAmount = 100 ether;
        giveTokens(weth, wethAmount);
        weth.approve(address(wethJoin), type(uint256).max);
        wethJoin.join(address(this), wethAmount);
        (,uint256 rate, uint256 spot,,) = vat.ilks("ETH-A");
        int256 dart = int256(spot * wethAmount / rate);
        vat.frob("ETH-A", address(this), address(this), address(this), int256(wethAmount), dart);
        hevm.warp(block.timestamp + 1 days);
        jug.drip("ETH-A");
    }

    function trigger_next_liquidation_job(bytes32 network, LiquidatorJob liquidator) internal {
        // TODO dont actually trigger liquidation here
        (bool canWork, bytes memory args) = liquidator.workable(network);
        assertTrue(canWork, "Expecting to be able to execute.");
        // No need to actually execute as the detection of a successful job will execute
        //(bool success,) = target.call(args);
        //assertTrue(success, "Execution should have succeeded.");
    }

    function verify_no_liquidation_job(bytes32 network, LiquidatorJob liquidator) internal {
        (bool canWork, bytes memory args) = liquidator.workable(network);
        assertTrue(!canWork, "Expecting NOT to be able to execute.");
        bytes memory expectedArgs = "No auctions";
        for (uint256 i = 0; i < expectedArgs.length; i++) {
            assertEq(args[i], expectedArgs[i]);
        }
    }

    function test_eth_a() public {
        // Setup auction
        uint256 auctionId = wethClip.kicks() + 1;
        dog.bark("ETH-A", address(this), address(this));
        assertEq(wethClip.kicks(), auctionId);
        (,uint256 tab,,,,) = wethClip.sales(auctionId);
        assertTrue(tab != 0, "auction didn't kick off");

        // Liquidation should not be available because the price is too high
        verify_no_liquidation_job(NET_A, liquidatorJob500);
        verify_no_liquidation_job(NET_A, liquidatorJob);

        // This will put it just below market price -- should trigger with only the no profit one
        // TODO - this can fail with market volatility -- should make this more robust by comparing Oracle to Uniswap price
        hevm.warp(block.timestamp + 33 minutes);

        verify_no_liquidation_job(NET_A, liquidatorJob500);
        uint256 vowDai = vat.dai(vow);
        trigger_next_liquidation_job(NET_A, liquidatorJob);

        // Auction should be cleared
        (,tab,,,,) = wethClip.sales(auctionId);
        assertEq(tab, 0);

        // Profit should go to vow
        assertGt(vat.dai(vow), vowDai);
    }

    function test_eth_a_profit() public {
        // Setup auction
        uint256 auctionId = wethClip.kicks() + 1;
        dog.bark("ETH-A", address(this), address(this));
        assertEq(wethClip.kicks(), auctionId);
        (,uint256 tab,,,,) = wethClip.sales(auctionId);
        assertTrue(tab != 0, "auction didn't kick off");

        // Liquidation should not be available because the price is too high
        verify_no_liquidation_job(NET_A, liquidatorJob500);

        // This will put it just below market price -- should still not trigger
        hevm.warp(block.timestamp + 33 minutes);
        verify_no_liquidation_job(NET_A, liquidatorJob500);

        // A little bit further
        hevm.warp(block.timestamp + 8 minutes);

        uint256 vowDai = vat.dai(vow);
        trigger_next_liquidation_job(NET_A, liquidatorJob500);

        // Auction should be cleared
        (,tab,,,,) = wethClip.sales(auctionId);
        assertEq(tab, 0);

        // Profit should go to vow
        assertGt(vat.dai(vow), vowDai);
    }

}
