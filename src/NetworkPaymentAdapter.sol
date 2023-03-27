// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2022 Dai Foundation
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

import {INetworkTreasury} from "./interfaces/INetworkTreasury.sol";

interface VestLike {
    function vest(uint256) external;
    function unpaid(uint256) external view returns (uint256);
}

interface DaiJoinLike {
    function dai() external view returns (address);
    function join(address, uint256) external;
}

interface DaiLike {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
}

/// @title Payment adapter to the keeper network treasury
/// @dev Sits between dss-vest and the keeper network treasury contract
contract NetworkPaymentAdapter {

    // --- Auth ---
    mapping (address => uint256) public wards;
    function rely(address usr) external auth {
        wards[usr] = 1;

        emit Rely(usr);
    }
    function deny(address usr) external auth {
        wards[usr] = 0;

        emit Deny(usr);
    }
    modifier auth {
        require(wards[msg.sender] == 1, "NetworkPaymentAdapter/not-authorized");
        _;
    }

    // --- Data ---
    VestLike public immutable vest;
    DaiJoinLike public immutable daiJoin;
    DaiLike public immutable dai;
    address public immutable vow;

    // --- Parameters ---
    uint256 public vestId;
    uint256 public bufferMax;
    uint256 public minimumPayment;
    INetworkTreasury public treasury;

    // --- Tracking ---
    uint256 public totalSent;

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, address data);
    event File(bytes32 indexed what, uint256 data);
    event TopUp(uint256 bufferSize, uint256 daiBalance, uint256 daiSent);

    // --- Errors ---
    error InvalidFileParam(bytes32 what);
    error UnauthorizedSender(address sender);
    error BufferFull(uint256 bufferSize, uint256 minimumPayment, uint256 bufferMax);
    error PendingDaiTooSmall(uint256 pendingDai, uint256 minimumPayment);

    constructor(address _vest, address _daiJoin, address _vow) {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);

        vest = VestLike(_vest);
        daiJoin = DaiJoinLike(_daiJoin);
        dai = DaiLike(daiJoin.dai());
        vow = _vow;

        dai.approve(address(daiJoin), type(uint256).max);
    }

    // --- Administration ---
    function file(bytes32 what, address data) external auth {
        if (what == "treasury") {
            treasury = INetworkTreasury(data);
        } else revert("NetworkPaymentAdapter/file-unrecognized-param");

        emit File(what, data);
    }

    function file(bytes32 what, uint256 data) external auth {
        if (what == "vestId") {
            vestId = data;
        } else if (what == "bufferMax") {
            bufferMax = data;
        } else if (what == "minimumPayment") {
            minimumPayment = data;
        } else revert("NetworkPaymentAdapter/file-unrecognized-param");

        emit File(what, data);
    }

    /**
     * @notice Top up the treasury with any outstanding DAI
     * @dev Only callable from treasury. Call canTopUp() to see if this will pass.
     */
    function topUp() external returns (uint256 daiSent) {
        if (msg.sender != address(treasury)) revert UnauthorizedSender(msg.sender);

        uint256 bufferSize = treasury.getBufferSize();
        uint256 pendingDai = vest.unpaid(vestId);
        uint256 _bufferMax = bufferMax;
        uint256 _minimumPayment = minimumPayment;

        if (bufferSize + _minimumPayment > _bufferMax) revert BufferFull(bufferSize, _minimumPayment, _bufferMax);
        else if (pendingDai >= _minimumPayment) {
            vest.vest(vestId);
            
            // Send DAI up to the maximum and the rest should go back into the surplus buffer
            // Use the balance in case someone sends DAI directly to this contract (can be used in emergency)
            uint256 daiBalance = dai.balanceOf(address(this));
            if (daiBalance + bufferSize > _bufferMax) {
                daiSent = _bufferMax - bufferSize;

                // Send the rest back to the surplus buffer
                daiJoin.join(vow, daiBalance - daiSent);
            } else {
                daiSent = daiBalance;
            }
            dai.transfer(address(treasury), daiSent);
            totalSent += daiSent;

            emit TopUp(bufferSize, daiBalance, daiSent);
        } else revert PendingDaiTooSmall(pendingDai, _minimumPayment);
    }

    /**
     * @notice Check if we can call the topUp() function.
     */
    function canTopUp() external view returns (bool) {
        uint256 bufferSize = treasury.getBufferSize();
        uint256 pendingDai = vest.unpaid(vestId);
        uint256 _minimumPayment = minimumPayment;

        return (bufferSize + _minimumPayment < bufferMax) && (pendingDai >= _minimumPayment);
    }

}
