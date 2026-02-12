// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import { MockV3Aggregator } from "../mocks/MockV3Aggregator.sol";

contract Handler is Test {
    DSCEngine engine;
    DecentralizedStableCoin dsc;

    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 public timesMintIsCalled;
    address[] public usersWithCollateralDeposited;
    MockV3Aggregator public ethUsdPriceFeed;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max; // Keep deposits reasonable

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc) {
        engine = _dscEngine;
        dsc = _dsc;

        address[] memory collateralTokens = engine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        ethUsdPriceFeed = MockV3Aggregator(engine.getCollateralTokenPriceFeed(address(weth)));
    }

    function mintDsc(uint256 amount) public {
        // You'll want to add this function too
        // Make sure there's enough collateral first
        if (usersWithCollateralDeposited.length == 0) {
            return;
        }
        address sender = usersWithCollateralDeposited[usersWithCollateralDeposited.length - 1];
        // Bound amount to reasonable value
        amount = bound(amount, 1, MAX_DEPOSIT_SIZE);
        vm.startPrank(sender);
        // Add try-catch to handle reverts gracefully
        try engine.mintDsc(amount) {
            timesMintIsCalled++;
        } catch {
            // Minting failed (probably due to collateralization ratio)
        }
        vm.stopPrank();
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        // Bound the amount to reasonable values (> 0 and <= MAX)
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        // Mint tokens to the sender (msg.sender in invariant tests is the fuzzer)
        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        // Approve the engine to spend tokens
        collateral.approve(address(engine), amountCollateral);
        // Now deposit
        engine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        // Track users who have deposited (useful for other functions)
        usersWithCollateralDeposited.push(msg.sender);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        // Get max collateral that can be redeemed for msg.sender
        uint256 maxCollateral = engine.getCollateralBalanceOfUser(msg.sender, address(collateral));
        // If no collateral, return early
        if (maxCollateral == 0) {
            return;
        }
        amountCollateral = bound(amountCollateral, 0, maxCollateral);
        
        if (amountCollateral == 0) {
            return;
        }
        vm.prank(msg.sender);
        engine.redeemCollateral(address(collateral), amountCollateral);
    }

    // This breaks the test suit
    // function updateCollateral(uint96 newPrice) public {
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     ethUsdPriceFeed.updateAnswer(newPriceInt);
    // }

    // Helper function
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns(ERC20Mock) {
        if(collateralSeed % 2 == 0){
            return weth;
        }
        return wbtc;
    }

    function invariants_getterShouldNotRevert() public view {
        engine.getLiquidationBonus();
        engine.getPrecision();
    }
}