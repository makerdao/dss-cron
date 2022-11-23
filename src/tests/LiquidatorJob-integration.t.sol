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

import "./DssCronBase.t.sol";
import {LiquidatorJob} from "../LiquidatorJob.sol";

contract LiquidatorIntegrationTest is DssCronBaseTest {

    address uniswapV3Callee;

    LiquidatorJob liquidatorJob;
    LiquidatorJob liquidatorJob500;

    function setUpSub() virtual override internal {
        uniswapV3Callee = 0xdB9C76109d102d2A1E645dCa3a7E671EBfd8e11A;

        // 0% profit expectation
        liquidatorJob = new LiquidatorJob(address(sequencer), address(mcd.daiJoin()), address(ilkRegistry), address(mcd.vow()), uniswapV3Callee, 0);

        // 5% profit expectation
        liquidatorJob500 = new LiquidatorJob(address(sequencer), address(mcd.daiJoin()), address(ilkRegistry), address(mcd.vow()), uniswapV3Callee, 500);

        // TODO clear out any existing auctions

        // Create an auction on ETH-A
        user.createAuction(mcd.wethAJoin(), 100 ether);
    }

    function trigger_next_liquidation_job(bytes32 network, LiquidatorJob liquidator) internal {
        // TODO dont actually trigger liquidation here
        (bool canWork,) = liquidator.workable(network);
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
        uint256 auctionId = mcd.wethAClip().kicks();
        (,uint256 tab,,,,) = mcd.wethAClip().sales(auctionId);
        assertTrue(tab != 0, "auction didn't kick off");

        // Liquidation should not be available because the price is too high
        verify_no_liquidation_job(NET_A, liquidatorJob500);
        verify_no_liquidation_job(NET_A, liquidatorJob);

        // This will put it just below market price -- should trigger with only the no profit one
        // TODO - this can fail with market volatility -- should make this more robust by comparing Oracle to Uniswap price
        GodMode.vm().warp(block.timestamp + 33 minutes);

        verify_no_liquidation_job(NET_A, liquidatorJob500);
        uint256 vowDai = mcd.vat().dai(address(mcd.vow()));
        trigger_next_liquidation_job(NET_A, liquidatorJob);

        // Auction should be cleared
        (,tab,,,,) = mcd.wethAClip().sales(auctionId);
        assertEq(tab, 0);

        // Profit should go to vow
        assertGt(mcd.vat().dai(address(mcd.vow())), vowDai);
    }

    function test_eth_a_profit() public {
        // Setup auction
        uint256 auctionId = mcd.wethAClip().kicks();
        (,uint256 tab,,,,) = mcd.wethAClip().sales(auctionId);
        assertTrue(tab != 0, "auction didn't kick off");

        // Liquidation should not be available because the price is too high
        verify_no_liquidation_job(NET_A, liquidatorJob500);

        // This will put it just below market price -- should still not trigger
        GodMode.vm().warp(block.timestamp + 33 minutes);
        verify_no_liquidation_job(NET_A, liquidatorJob500);

        // A little bit further
        GodMode.vm().warp(block.timestamp + 8 minutes);

        uint256 vowDai = mcd.vat().dai(address(mcd.vow()));
        trigger_next_liquidation_job(NET_A, liquidatorJob500);

        // Auction should be cleared
        (,tab,,,,) = mcd.wethAClip().sales(auctionId);
        assertEq(tab, 0);

        // Profit should go to vow
        assertGt(mcd.vat().dai(address(mcd.vow())), vowDai);
    }

}
