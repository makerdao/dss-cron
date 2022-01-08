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
import {Sequencer} from "../Sequencer.sol";
import {LiquidatorJob} from "../LiquidatorJob.sol";
import {LerpJob} from "../LerpJob.sol";

interface Hevm {
    function warp(uint256) external;
    function roll(uint256) external;
    function store(address,bytes32,bytes32) external;
    function load(address,bytes32) external view returns (bytes32);
    function expectRevert(bytes calldata) external;
}

interface AuthLike {
    function wards(address) external returns (uint256);
}

interface IlkRegistryLike {
    function list() external view returns (bytes32[] memory);
}

interface VatLike {
    function ilks(bytes32) external view returns (uint256, uint256, uint256, uint256, uint256);
    function slip(bytes32, address, int256) external;
    function frob(bytes32, address, address, address, int256, int256) external;
    function init(bytes32) external;
    function file(bytes32, bytes32, uint256) external;
    function hope(address) external;
    function dai(address) external view returns (uint256);
    function Line() external view returns (uint256);
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

// Integration tests against live MCD
abstract contract DssCronBaseTest is DSTest {

    uint256 constant WAD = 10 ** 18;
    uint256 constant RAY = 10 ** 27;
    uint256 constant RAD = 10 ** 45;

    Hevm hevm;

    IlkRegistryLike ilkRegistry;
    VatLike vat;
    DaiJoinLike daiJoin;
    TokenLike dai;
    address vow;
    Sequencer sequencer;

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
        vat = VatLike(0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B);
        daiJoin = DaiJoinLike(0x9759A6Ac90977b93B58547b4A71c78317f391A28);
        dai = TokenLike(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        vow = 0xA950524441892A31ebddF91d3cEEFa04Bf454466;
        
        // Add a default network
        sequencer.addNetwork(NET_A);
        
        setUpSub();
    }

    function setUpSub() virtual internal;

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

}
