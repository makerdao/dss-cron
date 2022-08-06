// SPDX-FileCopyrightText: © 2022 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import "./DssCronBase.t.sol";

import {RwaJarJobFactory} from "../RwaJarJobFactory.sol";

import {RwaRegistry} from "mip21-rwa-registry/RwaRegistry.sol";

import "dss-interfaces/Interfaces.sol";

interface JoinFabLike {
    function vat() external view returns (address);
    function newGemJoin(address _owner, bytes32 _ilk, address _gem) external returns (address join);
    function newGemJoin5(address _owner, bytes32 _ilk, address _gem) external returns (address join);
    function newAuthGemJoin(address _owner, bytes32 _ilk, address _gem) external returns (address join);
}

interface RwaTokenLike {
    function symbol() external view returns (string memory);
    function totalSupply() external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function scaledBalanceOf(address) external view returns (uint256);
    function decimals() external view returns (uint8);
}

interface RwaJarLike {
    function daiJoin() external returns(address);
    function dai() external returns(address);
    function chainlog() external returns(address);
    function void() external;
    function toss(uint256) external;
}
interface RwaUrnLike {
    function wards(address) external returns (uint256);
    function rely(address) external;
    function deny(address) external;
    function hope(address) external;
    function lock(uint256) external;
    function nope(address) external;
    function draw(uint256) external;
}

interface RwaLiquidationLike {
    function wards(address) external returns (uint256);
    function ilks(bytes32) external
        returns (
            string memory,
            address,
            uint48,
            uint48
        );
    function rely(address) external;
    function deny(address) external;
    function init(
        bytes32,
        uint256,
        string calldata,
        uint48
    ) external;
    function tell(bytes32) external;
    function cure(bytes32) external;
    function cull(bytes32) external;
    function good(bytes32) external view;
}


contract RwaJarJobFactoryTest is DssCronBaseTest {
    using GodMode for *;

    bytes32 constant RWAA = "RWA-A";
    bytes32 constant RWAB = "RWA-B";
    bytes32 constant RWAC = "RWA-C";
    bytes32 constant RWAD = "RWA-D";

    bytes32[] internal rwaIlks = [RWAA, RWAB, RWAC, RWAD];
    string[4] internal tokenSymbols = ["RWAA", "RWAB", "RWAC", "RWAD"];
    string[4] internal tokenNames = ["RWA Token A", "RWA Token B", "RWA Token C", "RWA Token D"];

    bytes32 constant URN = "urn";
    bytes32 constant LIQUIDATION_ORACLE = "liquidationOracle";
    bytes32 constant JAR = "jar";

    bytes32[] internal _names = [URN, LIQUIDATION_ORACLE, JAR];
    
    mapping(bytes32 => address) public rwaTokens;
    mapping(bytes32 => address) public rwaUrns;
    mapping(bytes32 => address) public rwaJars;

    RwaUrnLike internal rwaUrn;
    RwaJarLike internal rwaJar;
    RwaRegistry internal rwaRegistry;

    RwaJarJobFactory public rwaJarJob;

    event CreateJarJob(address indexed jar);
    event RemoveJarJob(address indexed jar);

    function setUpSub() virtual override internal {
        createRwaRegistryAndComponents(0);

        // execute the JarJobFactory once every 15 days
        rwaJarJob = new RwaJarJobFactory(
            address(sequencer),
            address(rwaRegistry),
            15 days
        );
        sequencer.rely(address(rwaJarJob));

        // Clear out all existing factory job by moving ahead 1 years
        GodMode.vm().warp(block.timestamp + 365 days * 1);
    }

    function testFactoryDeploysNewJarJobs() public {
        // on fresh rwa implementaion deploys a new jar job
        (bool canWork, bytes memory args) = rwaJarJob.workable(NET_A);
        assertTrue(canWork, "Should be able to work");

        // set up for event emmission test
        vm.expectEmit(true, false, false, false);
        emit CreateJarJob(address(rwaJars[RWAA]));

        // complete any required job
        rwaJarJob.work(NET_A, args);

        assertTrue(sequencer.numJobs() == 1, "Should have 1 job");
        (canWork, args) = rwaJarJob.workable(NET_A);
        assertTrue(!canWork, "Should not be able to work");

        // deploy another collateral - RWAB


        _addAnotherJar(1);
        assertTrue(rwaRegistry.count() == 2, "Should have 2 jars");


        // check jobs for next run every 15 days - is a new job deployed?
        GodMode.vm().warp(block.timestamp + 15 days * 1);

        (canWork, args) = rwaJarJob.workable(NET_A);
        assertTrue(canWork, "Should be able to work");

        // set up for event emmission test
        vm.expectEmit(true, false, false, false);
        emit CreateJarJob(address(rwaJars[RWAB]));

        // complete any required job
        rwaJarJob.work(NET_A, args);
        assertTrue(sequencer.numJobs() == 2, "Should have 2 jobs");

        // finalize job 
        // Make a jar not "ACTIVE" to see if JobFactory removes the Job
        rwaRegistry.finalize(RWAB); 
        // For next job run 
        GodMode.vm().warp(block.timestamp + 15 days * 1);
        assertTrue(sequencer.numJobs() == 2, "Should have 2 jobs");

        (canWork, args) = rwaJarJob.workable(NET_A);
        assertTrue(canWork, "Should be able to work");

        rwaJarJob.work(NET_A, args);
        assertTrue(sequencer.numJobs() == 1, "Should have 1 jobs");

        rwaRegistry.finalize(RWAA); 

        GodMode.vm().warp(block.timestamp + 15 days * 1);
        

        (canWork, args) = rwaJarJob.workable(NET_A);
        assertTrue(canWork, "Should be able to work");

        // set up for event emmission test
        vm.expectEmit(true, false, false, false);
        emit RemoveJarJob(address(rwaJars[RWAA]));

        rwaJarJob.work(NET_A, args);
        assertTrue(sequencer.numJobs() == 0, "Should have 0 jobs");
    }

    function createRwaRegistryAndComponents(uint256 ilkIndex) internal {
        // authorize this contract to create collateral and tokens
        mcd.vat().setWard(address(this), 1);

        // create RWA registry
        rwaRegistry = new RwaRegistry();

        // create RWA component variants for registry

        uint88[] memory variants = _createVariants();
        // Add RWA assets to forked MCD 
        addIlk(ilkIndex);
        deployRwaToken(ilkIndex);
        
        // deploy components and register addresses
        address[] memory addrs = new address[](3);
        addrs[0] =  deployUrn(rwaIlks[ilkIndex]);
        addrs[1] = mcd.chainlog().getAddress("MIP21_LIQUIDATION_ORACLE");
        addrs[2] = deployJar(rwaIlks[ilkIndex]);
        rwaRegistry.add(rwaIlks[ilkIndex], _names, addrs, variants);
    }

    function _addAnotherJar(uint256 ilkIndex) internal {
        // create RWA component variants for registry
        address[] memory addrs = new address[](3);
        addrs[0] = deployJar(rwaIlks[ilkIndex]);
        addrs[1] = mcd.chainlog().getAddress("MIP21_LIQUIDATION_ORACLE");
        addrs[2] = deployJar(rwaIlks[ilkIndex]);
        rwaRegistry.add(rwaIlks[ilkIndex], _names, addrs, _createVariants());
    }


    function addIlk(uint i) internal {
        mcd.vat().init(rwaIlks[i]);
        emit log_bytes32(rwaIlks[i]);    
    }

    function deployRwaToken(uint256 rwaIndex) internal returns (address) {
        address temp = deployCode("out/RwaToken.sol/RwaToken.json",  abi.encode(tokenNames[rwaIndex], tokenSymbols[rwaIndex]));
        rwaTokens[rwaIlks[rwaIndex]] = temp;
        return temp;
    }

    function deployUrn(bytes32 ilk) internal returns (address){
        JoinFabLike joinFab = JoinFabLike(mcd.chainlog().getAddress("JOIN_FAB"));
        address mcdPauseProxy = mcd.chainlog().getAddress("MCD_PAUSE_PROXY");
        address mcdVat = mcd.chainlog().getAddress("MCD_VAT");
        address mcdJug = mcd.chainlog().getAddress("MCD_JUG");
        address daiJoin = mcd.chainlog().getAddress("MCD_JOIN_DAI");
        address destination = address(this);
        address rwaJoin = joinFab.newAuthGemJoin(mcdPauseProxy, ilk, rwaTokens[ilk]);
        address temp = deployCode("out/RwaUrn2.sol/RwaUrn2.json", abi.encode(mcdVat, mcdJug, rwaJoin, daiJoin, destination));
        RwaUrnLike(temp).rely(mcdPauseProxy);
        RwaUrnLike(temp).deny(address(this));
        rwaUrns[ilk] = temp;
        return temp;
    }

    function _createVariants() internal pure returns (uint88[] memory) {
        uint88[] memory variants = new uint88[](3);
        variants[0] = 1;
        variants[1] = 1;
        variants[2] = 1;
        return variants;
    }


    function deployJar(bytes32 ilk) internal returns (address){
        address changelog = mcd.chainlog().getAddress("CHANGELOG");
        address temp = deployCode("out/RwaJar.sol/RwaJar.json", abi.encode(changelog));
        rwaJars[ilk] = temp;
        return temp;
    }

    function testDeployedRwaTokens() internal {
        assertEq(RwaTokenLike(rwaTokens[RWAA]).symbol(), "RWAA");
    }

    function testRegistryExists() public {
        assertEq(rwaRegistry.listSupportedComponents().length, 5);
        assertEq(rwaRegistry.count(), 1);

        // ilks are created
        assertEq(rwaRegistry.ilks(0), RWAA);
    
        // ilks RWAA is deployed with an urn and jar
        bytes32[] memory components = rwaRegistry.listComponentNamesOf(RWAA);
        assertEq(components.length, 3);
        assertEq(components[0], _names[0 /*URN*/]);
        assertEq(components[1], _names[1 /*LIQUIDATION_ORACLE*/]);
        assertEq(components[2], _names[2 /*JAR*/]);
    }
}

