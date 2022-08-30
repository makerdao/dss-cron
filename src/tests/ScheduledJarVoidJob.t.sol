// SPDX-FileCopyrightText: © 2022 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import "./DssCronBase.t.sol";

import {ScheduledJarVoidJob} from "../ScheduledJarVoidJob.sol";

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

contract ScheduledJarVoidJobTest is DssCronBaseTest {
    using GodMode for *;
    using stdStorage for StdStorage;


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

    uint256 testDaiAmount = 10_000 * WAD;

    ScheduledJarVoidJob public jarJob;

    event Toss(address indexed usr, uint256 wad);
    function setUpSub() virtual override internal {
        createRwaRegistryAndComponents(0);

        // set up a new sceheduledJar job

        jarJob = new ScheduledJarVoidJob(
            address(sequencer),
            rwaJars[RWAA],
            15 days
        );
        sequencer.rely(address(jarJob));

        // Clear out all existing factory job by moving ahead 1 years
        GodMode.vm().warp(block.timestamp + 365 days * 1);
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

    function testJarVoidedWhenAboveThreshold() public {
        // create some DAI and send to the Jar
        _createFakeDai(address(this), testDaiAmount);
        mcd.dai().transfer(rwaJars[RWAA],testDaiAmount);

        // check that the Jar has the correct balance and check Dai supply before   
        assertEq(mcd.dai().balanceOf(address(jarJob.rwaJar())), testDaiAmount);
        uint256 daiSupplyBefore = mcd.dai().totalSupply();

        // check whether the job needs to run     
        (bool canWork, bytes memory args) = jarJob.workable(NET_A);
        assertTrue(canWork, "Should be able to work");

        // set up for event emmission test
        vm.expectEmit(true, false, false, false);
        emit Toss(rwaJars[RWAA], testDaiAmount);

        // run the job
        jarJob.work(NET_A, args);

        uint256 daiSupplyAfter = mcd.dai().totalSupply();
        uint256 expectedDaiSupply = daiSupplyBefore - testDaiAmount;

        assertEq(mcd.dai().balanceOf(address(jarJob.rwaJar())), 0, "Balance of RwaJar is not zero");
        assertEq(daiSupplyAfter, expectedDaiSupply, "Total supply of Dai did not change after burn");

        // for next cycle
        // check that the job does not execute if the jar has a balance below the threshold

        // move forward 15 days
        GodMode.vm().warp(block.timestamp + 15 days * 1);

        // lets add DAI in the jar in the amount of the threshold
        _createFakeDai(address(this), jarJob.THRESHOLD());
        mcd.dai().transfer(rwaJars[RWAA],jarJob.THRESHOLD());
        assertEq(mcd.dai().balanceOf(address(jarJob.rwaJar())), jarJob.THRESHOLD(), "Balance of RwaJar is not zero");
        
        (canWork, args) = jarJob.workable(NET_A);
        assertTrue(!canWork, "Should not be able to work");

    }

    
    function _createFakeDai(address usr, uint256 wad) private {
        // create dai in the test contract 
   
        stdstore.target(address(mcd.vat())).sig("dai(address)").with_key(address(this)).checked_write(_rad(wad));
        stdstore
            .target(address(mcd.vat()))
            .sig("can(address,address)")
            .with_key(address(this))
            .with_key(address(mcd.daiJoin()))
            .checked_write(uint256(1));
        // // Converts the minted Dai into ERC-20 Dai and sends it to `usr`.
        mcd.daiJoin().exit(usr, wad);
        assertEq(mcd.dai().balanceOf(usr), wad, "Balance of user is not equal to wad");
    }

    function _rad(uint256 wad) internal pure returns (uint256) {
        return (wad * RAY);
    }
    
}
