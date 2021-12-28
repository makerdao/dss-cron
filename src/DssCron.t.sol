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

import "ds-test/test.sol";
import {Sequencer} from "./Sequencer.sol";
import {AutoLineJob} from "./AutoLineJob.sol";
import {LiquidatorJob} from "./LiquidatorJob.sol";

interface Hevm {
    function warp(uint256) external;
    function roll(uint256) external;
    function store(address,bytes32,bytes32) external;
    function load(address,bytes32) external view returns (bytes32);
}

interface AuthLike {
    function wards(address) external returns (uint256);
}

interface IlkRegistryLike {
    function list() external view returns (bytes32[] memory);
}

interface AutoLineLike {
    function vat() external view returns (address);
    function ilks(bytes32) external view returns (uint256, uint256, uint48, uint48, uint48);
    function exec(bytes32) external returns (uint256);
    function setIlk(bytes32,uint256,uint256,uint256) external;
    function remIlk(bytes32) external;
}

interface VatLike {
    function ilks(bytes32) external view returns (uint256, uint256, uint256, uint256, uint256);
    function slip(bytes32, address, int256) external;
    function frob(bytes32, address, address, address, int256, int256) external;
    function init(bytes32) external;
    function file(bytes32, bytes32, uint256) external;
    function hope(address) external;
    function dai(address) external view returns (uint256);
}

interface DaiJoinLike {
}

interface TokenLike {
    function totalSupply() external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
    function allowance(address, address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}

interface JoinLike {
    function join(address, uint256) external;
}

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

// Integration tests against live MCD
contract DssCronTest is DSTest {

    uint256 constant WAD = 10 ** 18;
    uint256 constant RAY = 10 ** 27;
    uint256 constant RAD = 10 ** 45;

    Hevm hevm;

    IlkRegistryLike ilkRegistry;
    AutoLineLike autoline;
    VatLike vat;
    DaiJoinLike daiJoin;
    TokenLike dai;
    TokenLike weth;
    JoinLike wethJoin;
    ClipLike wethClip;
    JugLike jug;
    DogLike dog;
    address vow;
    address uniswapV3Callee;
    Sequencer sequencer;

    // Jobs
    AutoLineJob autoLineJob;
    LiquidatorJob liquidatorJob;
    LiquidatorJob liquidatorJob500;

    bytes32 constant NET_A = "NTWK-A";
    bytes32 constant NET_B = "NTWK-B";
    bytes32 constant NET_C = "NTWK-C";
    bytes32 constant ILK = "TEST-ILK";

    function setUp() public {
        hevm = Hevm(HEVM_ADDRESS);

        sequencer = new Sequencer();
        sequencer.file("window", 12);       // Give 12 block window for each network (~3 mins)
        assertEq(sequencer.window(), 12);

        ilkRegistry = IlkRegistryLike(0x5a464C28D19848f44199D003BeF5ecc87d090F87);
        autoline = AutoLineLike(0xC7Bdd1F2B16447dcf3dE045C4a039A60EC2f0ba3);
        vat = VatLike(0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B);
        daiJoin = DaiJoinLike(0x9759A6Ac90977b93B58547b4A71c78317f391A28);
        dai = TokenLike(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        weth = TokenLike(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        wethJoin = JoinLike(0x2F0b23f53734252Bda2277357e97e1517d6B042A);
        wethClip = ClipLike(0xc67963a226eddd77B91aD8c421630A1b0AdFF270);
        jug = JugLike(0x19c0976f590D67707E62397C87829d896Dc0f1F1);
        dog = DogLike(0x135954d155898D42C90D2a57824C690e0c7BEf1B);
        vow = 0xA950524441892A31ebddF91d3cEEFa04Bf454466;
        uniswapV3Callee = 0xdB9C76109d102d2A1E645dCa3a7E671EBfd8e11A;
        autoLineJob = new AutoLineJob(address(sequencer), address(ilkRegistry), address(autoline), 1000, 2000);                         // 10% / 20% bands
        liquidatorJob = new LiquidatorJob(address(sequencer), address(daiJoin), address(ilkRegistry), vow, uniswapV3Callee, 0);         // 0% profit expectation
        liquidatorJob500 = new LiquidatorJob(address(sequencer), address(daiJoin), address(ilkRegistry), vow, uniswapV3Callee, 500);    // 5% profit expectation
    }

    function giveAuthAccess(address _base, address target) internal {
        AuthLike base = AuthLike(_base);

        // Edge case - ward is already set
        if (base.wards(target) == 1) return;

        for (int i = 0; i < 100; i++) {
            // Scan the storage for the ward storage slot
            bytes32 prevValue = hevm.load(
                address(base),
                keccak256(abi.encode(target, uint256(i)))
            );
            hevm.store(
                address(base),
                keccak256(abi.encode(target, uint256(i))),
                bytes32(uint256(1))
            );
            if (base.wards(target) == 1) {
                // Found it
                return;
            } else {
                // Keep going after restoring the original value
                hevm.store(
                    address(base),
                    keccak256(abi.encode(target, uint256(i))),
                    prevValue
                );
            }
        }

        // We have failed if we reach here
        assertTrue(false);
    }

    function giveTokens(TokenLike token, uint256 amount) internal {
        // Edge case - balance is already set for some reason
        if (token.balanceOf(address(this)) == amount) return;

        for (uint256 i = 0; i < 200; i++) {
            // Scan the storage for the balance storage slot
            bytes32 prevValue = hevm.load(
                address(token),
                keccak256(abi.encode(address(this), uint256(i)))
            );
            hevm.store(
                address(token),
                keccak256(abi.encode(address(this), uint256(i))),
                bytes32(amount)
            );
            if (token.balanceOf(address(this)) == amount) {
                // Found it
                return;
            } else {
                // Keep going after restoring the original value
                hevm.store(
                    address(token),
                    keccak256(abi.encode(address(this), uint256(i))),
                    prevValue
                );
            }
        }

        // We have failed if we reach here
        assertTrue(false);
    }

    function test_sequencer_add_network() public {
        sequencer.addNetwork(NET_A);

        assertEq(sequencer.activeNetworks(0), NET_A);
        assertTrue(sequencer.networks(NET_A));
        assertEq(sequencer.count(), 1);
    }

    function testFail_sequencer_add_dupe_network() public {
        sequencer.addNetwork(NET_A);
        sequencer.addNetwork(NET_A);
    }

    function test_sequencer_add_remove_network() public {
        sequencer.addNetwork(NET_A);
        sequencer.removeNetwork(0);

        assertTrue(!sequencer.networks(NET_A));
        assertEq(sequencer.count(), 0);
    }

    function test_sequencer_add_remove_networks() public {
        sequencer.addNetwork(NET_A);
        sequencer.addNetwork(NET_B);
        sequencer.addNetwork(NET_C);

        assertEq(sequencer.count(), 3);
        assertEq(sequencer.activeNetworks(0), NET_A);
        assertEq(sequencer.activeNetworks(1), NET_B);
        assertEq(sequencer.activeNetworks(2), NET_C);

        // Should move NET_C (last element) to slot 0
        sequencer.removeNetwork(0);


        assertEq(sequencer.count(), 2);
        assertEq(sequencer.activeNetworks(0), NET_C);
        assertEq(sequencer.activeNetworks(1), NET_B);
    }

    function test_sequencer_rotation() public {
        sequencer.addNetwork(NET_A);
        sequencer.addNetwork(NET_B);
        sequencer.addNetwork(NET_C);

        bytes32[3] memory networks = [NET_A, NET_B, NET_C];

        for (uint256 i = 0; i < sequencer.window() * 10; i++) {
            assertTrue(sequencer.isMaster(networks[0]) == ((block.number / sequencer.window()) % sequencer.count() == 0));
            assertTrue(sequencer.isMaster(networks[1]) == ((block.number / sequencer.window()) % sequencer.count() == 1));
            assertTrue(sequencer.isMaster(networks[2]) == ((block.number / sequencer.window()) % sequencer.count() == 2));
            assertEq(
                (sequencer.isMaster(networks[0]) ? 1 : 0) +
                (sequencer.isMaster(networks[1]) ? 1 : 0) +
                (sequencer.isMaster(networks[2]) ? 1 : 0)
            , 1);       // Only one active at a time

            hevm.roll(block.number + 1);
        }
    }

    // --- AutoLineJob tests ---

    function mint(bytes32 ilk, uint256 wad) internal {
        (uint256 Art,,,,) = vat.ilks(ilk);
        vat.slip(ilk, address(this), int256(wad));
        vat.frob(ilk, address(this), address(this), address(this), int256(wad), int256(wad));
        (uint256 nextArt,,,,) = vat.ilks(ilk);
        assertEq(nextArt, Art + wad);
    }
    function repay(bytes32 ilk, uint256 wad) internal {
        (uint256 Art,,,,) = vat.ilks(ilk);
        vat.frob(ilk, address(this), address(this), address(this), -int256(wad), -int256(wad));
        vat.slip(ilk, address(this), -int256(wad));
        (uint256 nextArt,,,,) = vat.ilks(ilk);
        assertEq(nextArt, Art - wad);
    }

    function clear_other_ilks(bytes32 network) internal {
        while(true) {
            (bool canExec, address target, bytes memory execPayload) = autoLineJob.getNextJob(network);
            if (!canExec) break;
            bytes32 ilk = abi.decode(execPayload, (bytes32));
            if (ilk == ILK) break;
            (,,, uint256 line,) = vat.ilks(ilk);
            (bool success, bytes memory result) = target.call(execPayload);
            uint256 newLine = abi.decode(result, (uint256));
            assertTrue(success, "Execution should have succeeded.");
            assertTrue(line != newLine, "Line should have changed.");
        }
    }

    function init_autoline() internal {
        giveAuthAccess(address(vat), address(this));
        giveAuthAccess(address(autoline), address(this));

        // Setup a dummy ilk in the vat
        vat.init(ILK);
        vat.file(ILK, "spot", RAY);
        vat.file(ILK, "line", 1_000 * RAD);
        autoline.setIlk(ILK, 100_000 * RAD, 1_000 * RAD, 8 hours);

        // Add to ilk regitry as well (only care about the ilk ids array)
        bytes32 pos = bytes32(uint256(5));
        uint256 size = uint256(hevm.load(address(ilkRegistry), pos));
        hevm.store(
            address(ilkRegistry),
            bytes32(uint256(keccak256(abi.encode(pos))) + size),
            ILK
        );      // Append new ilk
        hevm.store(
            address(ilkRegistry),
            pos,
            bytes32(size + 1)
        );      // Increase size of array

        // Add a default network
        sequencer.addNetwork(NET_A);

        // Clear out any autolines that need to be triggered
        clear_other_ilks(NET_A);
    }

    function trigger_next_autoline_job(bytes32 network, bytes32 ilk) internal {
        (bool canExec, address target, bytes memory execPayload) = autoLineJob.getNextJob(network);
        assertTrue(canExec, "Expecting to be able to execute.");
        assertEq(target, address(autoline));
        bytes memory expectedPayload = abi.encodeWithSelector(AutoLineLike.exec.selector, ilk);
        for (uint256 i = 0; i < expectedPayload.length; i++) {
            assertEq(execPayload[i], expectedPayload[i]);
        }
        (,,, uint256 line,) = vat.ilks(ilk);
        (bool success, bytes memory result) = target.call(execPayload);
        uint256 newLine = abi.decode(result, (uint256));
        assertTrue(success, "Execution should have succeeded.");
        assertTrue(line != newLine, "Line should have changed.");
    }

    function verify_no_autoline_job(bytes32 network) internal {
        (bool canExec, address target, bytes memory execPayload) = autoLineJob.getNextJob(network);
        assertTrue(!canExec, "Expecting NOT to be able to execute.");
        assertEq(target, address(0));
        bytes memory expectedPayload = "No ilks ready";
        for (uint256 i = 0; i < expectedPayload.length; i++) {
            assertEq(execPayload[i], expectedPayload[i]);
        }
    }

    function test_autolinejob_raise_line() public {
        init_autoline();

        verify_no_autoline_job(NET_A);

        mint(ILK, 110 * WAD);           // Over the threshold to raise the DC (10%)

        trigger_next_autoline_job(NET_A, ILK);

        verify_no_autoline_job(NET_A);
    }

    function test_autolinejob_disabled() public {
        init_autoline();

        verify_no_autoline_job(NET_A);

        mint(ILK, 110 * WAD);

        // Disable the autoline
        autoline.remIlk(ILK);

        verify_no_autoline_job(NET_A);
    }

    function test_autolinejob_same_block() public {
        init_autoline();

        verify_no_autoline_job(NET_A);

        mint(ILK, 200 * WAD);
        trigger_next_autoline_job(NET_A, ILK);
        mint(ILK, 200 * WAD);
        verify_no_autoline_job(NET_A);
    }

    function test_autolinejob_under_ttl() public {
        init_autoline();

        verify_no_autoline_job(NET_A);

        mint(ILK, 200 * WAD);
        trigger_next_autoline_job(NET_A, ILK);

        hevm.roll(block.number + 1);
        
        // It's possible some other ilks are valid now
        clear_other_ilks(NET_A);

        mint(ILK, 200 * WAD);
        verify_no_autoline_job(NET_A);
    }

    function test_autolinejob_diff_block_ttl() public {
        init_autoline();

        verify_no_autoline_job(NET_A);

        mint(ILK, 200 * WAD);
        trigger_next_autoline_job(NET_A, ILK);

        hevm.roll(block.number + 1);
        hevm.warp(block.timestamp + 8 hours);
        
        // It's possible some other ilks are valid now
        clear_other_ilks(NET_A);

        mint(ILK, 200 * WAD);
        trigger_next_autoline_job(NET_A, ILK);
    }

    function test_autolinejob_lower_line() public {
        init_autoline();

        verify_no_autoline_job(NET_A);

        mint(ILK, 1000 * WAD);
        trigger_next_autoline_job(NET_A, ILK);
        hevm.roll(block.number + 1);
        hevm.warp(block.timestamp + 8 hours);
        clear_other_ilks(NET_A);
        mint(ILK, 1000 * WAD);
        trigger_next_autoline_job(NET_A, ILK);
        hevm.roll(block.number + 1);
        repay(ILK, 200 * WAD);      // 20% threshold of gap
        trigger_next_autoline_job(NET_A, ILK);
        verify_no_autoline_job(NET_A);
    }

    function test_autolinejob_autoline_param_change() public {
        init_autoline();

        // Adjust max line / gap
        autoline.setIlk(ILK, 6_000 * RAD, 5_000 * RAD, 8 hours);

        // Should be triggerable now as we are 1000 away from
        // the line which is 80% above the line - gap
        trigger_next_autoline_job(NET_A, ILK);
    }

    function test_autolinejob_max_line_within_do_nothing_range() public {
        init_autoline();

        // Set the new gap / maxLine to be slightly less
        autoline.setIlk(ILK, 999 * RAD, 999 * RAD, 8 hours);

        // This should be within the do-nothing range, but should still
        // trigger due to the next adjustment being set to maxLine
        trigger_next_autoline_job(NET_A, ILK);
    }

    // --- LiquidatorJob tests ---

    function init_liquidator() internal {
        // Add a default network
        sequencer.addNetwork(NET_A);

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
        (bool canExec, address target,) = liquidator.getNextJob(network);
        assertTrue(canExec, "Expecting to be able to execute.");
        assertEq(target, address(liquidator));
        // No need to actually execute as the detection of a successful job will execute
        //(bool success,) = target.call(execPayload);
        //assertTrue(success, "Execution should have succeeded.");
    }

    function verify_no_liquidation_job(bytes32 network, LiquidatorJob liquidator) internal {
        (bool canExec, address target, bytes memory execPayload) = liquidator.getNextJob(network);
        assertTrue(!canExec, "Expecting NOT to be able to execute.");
        assertEq(target, address(0));
        bytes memory expectedPayload = "No auctions";
        for (uint256 i = 0; i < expectedPayload.length; i++) {
            assertEq(execPayload[i], expectedPayload[i]);
        }
    }

    function test_liquidation_eth_a() public {
        init_liquidator();

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
        hevm.warp(block.timestamp + 30 minutes);

        verify_no_liquidation_job(NET_A, liquidatorJob500);
        uint256 vowDai = vat.dai(vow);
        trigger_next_liquidation_job(NET_A, liquidatorJob);

        // Auction should be cleared
        (,tab,,,,) = wethClip.sales(auctionId);
        assertEq(tab, 0);

        // Profit should go to vow
        assertGt(vat.dai(vow), vowDai);
    }

    function test_liquidation_eth_a_profit() public {
        init_liquidator();

        // Setup auction
        uint256 auctionId = wethClip.kicks() + 1;
        dog.bark("ETH-A", address(this), address(this));
        assertEq(wethClip.kicks(), auctionId);
        (,uint256 tab,,,,) = wethClip.sales(auctionId);
        assertTrue(tab != 0, "auction didn't kick off");

        // Liquidation should not be available because the price is too high
        verify_no_liquidation_job(NET_A, liquidatorJob500);

        // This will put it just below market price -- should still not trigger
        hevm.warp(block.timestamp + 30 minutes);
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
