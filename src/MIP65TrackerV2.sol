// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin-contracts/contracts/access/AccessControl.sol";

/**
 * @title MIP65 Tracker
 * @notice Off-chain accounting for MIP65.
 * @notice all timestamp are date, i.e.  UTC midnight, this allow to more easily correct wrong data
 * @notice most operations use int for quantities/amounts so you can correct a mistake by submitting -value.
 */
contract MIP65TrackerV2 is AccessControl {
    /**
     * @notice Allows a new asset to be used
     * @param asset Identification of the asset (short ID)
     */
    event AssetInit(string asset);
    /**
     * @notice Record an executed buy order for an asset
     * @param asset Identification of the asset
     * @param date Date in Unix time (midnight GMT)
     * @param qty If positive, amount bough (18 decimals). If negative, correction of a previous buy order
     * @param price Price of the buying order, per unit of asset (18 decimals)
     */
    event AssetBuy(string asset, uint date, int qty, int price);
    /**
     * @notice Record an executed sell order for an asset
     * @param asset Identification of the asset
     * @param date Date in Unix time (midnight GMT)
     * @param qty If positive, amount sold (18 decimals). If negative, correction of a previous sell order
     * @param price Price of the selling order, per unit of asset (18 decimals)
     */
    event AssetSell(string asset, uint date, int qty, int price);
    /**
     * @notice Update the asset metadata
     * @param asset Identification of the asset
     * @param date Date in Unix time (midnight GMT)
     * @param nav Net asset value (fair value) per unit of the asset (18 decimals).
     * @param yield Estimated instantaneous yield of the asset.
     * @param duration Estimated instantaneous effectve duration of the asset.
     * @param maturity Estimated instantaneous maturity of the asset.
     */
    event AssetUpdate(string asset, uint date, int nav, int yield, int duration, int maturity);
    /**
     * @notice Adding capital to MIP65
     * @param date Date in Unix time (midnight GMT), time of the vault drawdown.
     * @param amount Amount contributed to MIP65 in DAI (18 decimals), negative amount if correction.
     */
    event CapitalIn(uint date, int amount);
    /**
     * @notice Removing capital to MIP65, both through RWAJar or to the vault.
     * @param date Date in Unix time (midnight GMT), time when t leaves MIP65 perimeter.
     * @param amount Amount contributed to MIP65 in DAI (18 decimals), negative amount if correction.
     */
    event CapitalOut(uint date, int amount);
    /**
     * @notice Record an expense to a MIP65 supplier
     * @param date Date in Unix time (midnight GMT)
     * @param amount Amount contributed to MIP65 in DAI (18 decimals), negative amount if correction.
     * @param reason Label for the expense (code of the suppler)
     */
    event Expense(uint date, int amount, string reason);
    /**
     * @notice Record an income inside MIP65. 
     * @param date Date in Unix time (midnight GMT)
     * @param amount Amount contributed to MIP65 in DAI (18 decimals), negative amount if correction.
     * @param reason Label for the income.
     */
    event Income(uint date, int amount, string reason);

    // Tracking for an asset
    struct Asset {
        string name;
        // updated with buy/sell operations
        int qty;
        // updated with update operaion
        uint date;
        int nav;
        int yield;
        int duration;
        int maturity;
    }

    // Light admin able to manage DATA and OPS roles.
    bytes32 public constant GUARDIAN_ROLE = keccak256(abi.encode("mip65.guardian.role"));
    // Able to update asset data (nav, yield, duration)
    bytes32 public constant DATA_ROLE = keccak256(abi.encode("mip65.data.role"));
    // Able to execute transactions (buy/se/capital in/capital out/expense/income)
    bytes32 public constant OPS_ROLE = keccak256(abi.encode("mip65.ops.role"));

    mapping (string => Asset) private _assets;
    string[] private _assetsIds;
    int private _cash;

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setRoleAdmin(GUARDIAN_ROLE, DEFAULT_ADMIN_ROLE);
        _grantRole(GUARDIAN_ROLE, _msgSender());
        _setRoleAdmin(DATA_ROLE, GUARDIAN_ROLE);
        _setRoleAdmin(OPS_ROLE, GUARDIAN_ROLE);
        _cash = 0;
    }

    function _checkDate(uint date) internal view {
        require(date != 0, "The timestamp can't be 0");
        require(date % 24*3600 == 0, "The date should be at UTC midnight");
        require(date < block.timestamp, "The date should not be in the future");
    }

    /**
     * @notice Allows a new asset to be used
     * @param asset Identification of the asset (short ID)
     */
    function init(string calldata asset) onlyRole(GUARDIAN_ROLE) external {
        _assets[asset] = Asset(asset, 0, 0, 0, 0, 0, 0);
        _assetsIds.push(asset);
        emit AssetInit(asset);
    }

    /**
     * @notice Record an executed buy order for an asset
     * @param asset Identification of the asset
     * @param date Date in Unix time (midnight GMT)
     * @param qty If positive, amount bough (18 decimals). If negative, correction of a previous buy order
     * @param price Price of the buying order, per unit of asset (18 decimals)
     */
    function buy(string calldata asset, uint date, int qty, int price) onlyRole(OPS_ROLE) external {
        _checkDate(date);
        Asset storage item = _assets[asset];
        item.qty += qty;
        _cash -= (qty * price) / 10**18;
        emit AssetBuy(asset, date, qty, price);
    }
    
    /**
     * @notice Record an executed sell order for an asset
     * @param asset Identification of the asset
     * @param date Date in Unix time (midnight GMT)
     * @param qty If positive, amount sold (18 decimals). If negative, correction of a previous sell order
     * @param price Price of the selling order, per unit of asset (18 decimals)
     */
    function sell(string calldata asset, uint date, int qty, int price) onlyRole(OPS_ROLE) external {
        _checkDate(date);
        Asset storage item = _assets[asset];
        item.qty -= qty;
        _cash += (qty * price) / 10**18;
        emit AssetSell(asset, date, qty, price);
    }

    /**
     * @notice Update the asset metadata
     * @param asset Identification of the asset
     * @param date Date in Unix time (midnight GMT)
     * @param nav Net asset value (fair value) per unit of the asset (18 decimals).
     * @param yield Estmated instantaneous yield of the asset.
     * @param duration Estmated instantaneous effectve duration of the asset.
     * @param maturity Estmated instantaneous maturity of the asset.
     */
    function update(string calldata asset, uint date, int nav, int yield, int duration, int maturity) onlyRole(DATA_ROLE) external {
        _checkDate(date);
        Asset storage item = _assets[asset];
        item.nav = nav;
        item.yield = yield;
        item.duration = duration;
        item.maturity = maturity;
        emit AssetUpdate(asset, date, nav, yield, duration, maturity);
    }

    /**
     * @notice Adding capital to MIP65
     * @param date Date in Unix time (midnight GMT), time of the vault drawdown.
     * @param amount Amount contributed to MIP65 in DAI (18 decimals), negative amount if correction.
     */
    function addCapital(uint date, int amount) onlyRole(OPS_ROLE) external {
        _checkDate(date);
        _cash += amount;
        emit CapitalIn(date, amount);
    }

    /**
     * @notice Removing capital to MIP65, both through RWAJar or to the vault.
     * @param date Date in Unix time (midnight GMT), time when t leaves MIP65 perimeter.
     * @param amount Amount contributed to MIP65 in DAI (18 decimals), negative amount if correction.
     */
    function removeCapital(uint date, int amount) onlyRole(OPS_ROLE) external {
        _checkDate(date);
        _cash -= amount;
        emit CapitalOut(date, amount);
    }

    /**
     * @notice Record an expense to a MIP65 supplier
     * @param date Date in Unix time (midnight GMT)
     * @param amount Amount contributed to MIP65 in DAI (18 decimals), negative amount if correction.
     * @param reason Label for the expense (code of the suppler)
     */
    function expense(uint date, int amount, string memory reason) onlyRole(OPS_ROLE) external {
        _checkDate(date);
        _cash -= amount;
        emit Expense(date, amount, reason);
    }

    /**
     * @notice Record an income inside MIP65. 
     * @param date Date in Unix time (midnight GMT)
     * @param amount Amount contributed to MIP65 in DAI (18 decimals), negative amount if correction.
     * @param reason Label for the income.
     */
    function income(uint date, int amount, string memory reason) onlyRole(OPS_ROLE) external {
        _checkDate(date);
        _cash += amount;
        emit Income(date, amount, reason);
    }

    /**
     * @notice Return the net asset value of MIP65.
     * @return Net asset value (cash + assets).
     */
    function value() view external returns (int) {
        int val = 0;
        for(uint i = 0; i < _assetsIds.length; i++) {
            Asset memory item = _assets[_assetsIds[i]];
            val += (item.qty * item.nav) / 10**18;
        }
        return val + _cash;
    }

    /**
     * @notice Return the cash balance.
     * @return Amount of cash in MIP65 (18 decimals).
     */
    function cash() view external returns (int) {
        return _cash;
    }

    /**
     * @notice Return the net asset value of MIP65.
     * @return List of assets initialized.
     */
    function assets() view external returns (string[] memory) {
        return _assetsIds;
    }

    /**
     * @notice Provide details on a particular asset
     * @param asset Identification of the asset.
     * @return qty Quantity of unit of this asset currently hold by MIP65.
     * @return nav Last provided net asset value (fair value) per unit of the asset (18 decimals).
     * @return yield Last provided estimated instantaneous yield of the asset.
     * @return duration Last provided estimated instantaneous effectve duration of the asset.
     * @return maturity Last provided estimated instantaneous maturity of the asset.
     */
    function details(string calldata asset) view external returns (int qty, int nav, int yield, int duration, int maturity) {
        Asset memory item = _assets[asset];
        return (item.qty, item.nav, item.yield, item.duration, item.maturity);
    }
}
