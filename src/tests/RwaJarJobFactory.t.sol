// SPDX-FileCopyrightText: © 2022 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import "./DssCronBase.t.sol";

import {RwaJarJobFactory} from "../RwaJarJobFactory.sol";

import {RwaRegistry} from "mip21-rwa-registry/RwaRegistry.sol";


import "forge-std/console2.sol";
import "forge-std/Script.sol";

interface RwaTokenLike {
    function symbol() external view returns (string memory);
    function totalSupply() external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function scaledBalanceOf(address) external view returns (uint256);
    function decimals() external view returns (uint8);
}
contract RwaJarJobFactoryTest is DssCronBaseTest {
    using GodMode for *;

    bytes32 constant RWAA = "RWA-A";
    bytes32 constant RWAB = "RWA-B";
    bytes32 constant RWAC = "RWA-C";
    bytes32 constant RWAD = "RWA-D";

    bytes32[] internal rwaIlks = [RWAA, RWAB, RWAC, RWAD];

    mapping(bytes32 => address) public rwaTokens;
    RwaRegistry internal rwaRegistry;

    RwaJarJobFactory public rwaJarJobFactory;

    // string internal name = "RWA-A";
    // string internal symbol = "RWAA";

    
    // RwaToken rwaTokenB;
    // RwaToken rwaTokenC;
    // RwaToken rwaTokenD;

    function setUpSub() virtual override internal {
        createRwaRegistry();
    }


    function createRwaRegistry() internal {
        // require(mcd.vat.ilks().length = 50);
        
        rwaRegistry = new RwaRegistry();
        addRwasToIlk();
        deployRwaTokens();
        deployMip21Components();
        updateRwaRegistry();

        for (uint i=0; i < ilkRegistry.list().length; i++) {
            emit log_bytes32(ilkRegistry.list()[i]);
        }
        console2.log("Length", ilkRegistry.list().length);
    }

    function testRegistryExists() public {
        assertEq(rwaRegistry.listSupportedComponents().length, 5);
        // console2.log("Ilks", mcd.vat().ilks(RWAA));
        // assertEq(mcd.vat.ilks().length, 50);
    }

    function addRwasToIlk() internal {        
        mcd.vat().setWard(address(this), 1);
        for (uint i=0; i < rwaIlks.length; i++) {
            mcd.vat().init(rwaIlks[i]);
            emit log_bytes32(rwaIlks[i]);
        }
    }

    function deployRwaTokens() internal returns (address) {
        string[4] memory tokenNames = ["RWA Token A", "RWA Token B", "RWA Token C", "RWA Token D"];
        string[4] memory tokenSymbols = ["RWAA", "RWAB", "RWAC", "RWAD"];
        for (uint i=0; i < rwaIlks.length; i++) {
            console2.log("Deploying", tokenNames[i]);
            console2.log("Symbol", tokenSymbols[i]);
            address temp = deployCode("RwaToken.json",  abi.encode(tokenNames[i], tokenSymbols[i]));
            rwaTokens[rwaIlks[i]] = temp;
        }
        assertEq(RwaTokenLike(rwaTokens[RWAA]).symbol(), "RWAA");
        assertEq(RwaTokenLike(rwaTokens[RWAB]).symbol(), "RWAB");
        assertEq(RwaTokenLike(rwaTokens[RWAC]).symbol(), "RWAC");
        assertEq(RwaTokenLike(rwaTokens[RWAD]).symbol(), "RWAD");
        // use join_fab and do authgem join
    }

    function deployMip21Components() internal {
        console2.log("Code for deploying MIP21 components");

    }   

    function updateRwaRegistry() internal {
        console2.log("Code for deploying RWA registry");
    }
}
