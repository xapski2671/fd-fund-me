// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.19;

import { Test, console } from "forge-std/Test.sol";
import { FundMe } from "../src/FundMe.sol";
import { DeployFundMe } from "../script/deploy-fund-me.s.sol";

contract FundMeTest is Test {
    FundMe fundMe;

    address USER = makeAddr("user"); // a secondary EOA
    uint constant SEND_VALUE = 0.1 ether;
    uint constant STARTING_BALANCE = 10 ether;
    uint constant GAS_PRICE = 1; // artificial

    function setUp() external {
        DeployFundMe deployFundMe = new DeployFundMe();
        fundMe = deployFundMe.run();
        vm.deal(USER, STARTING_BALANCE);
        // setting USER balance to 10 ether note that this is done in the setup function
    }

    function testMinimumDollarIsFive() public {
        assertEq(fundMe.MINIMUM_USD(), 5e18);
    }

    function testOwnerisFundeMeTest() public {
        assertEq(fundMe.getOwner(), msg.sender);
    }

    function testPriceFeedVersion() public {
        uint version = fundMe.getVersion();
        assertEq(version, 4);
    }

    function testFundFailsWithoutEnoughETH() public {
        vm.expectRevert(); // the next line should revert
        fundMe.fund(); // called fund with 0 value, should revert
    }

    function testFundUpdatesFundedDataStructure() public {
        vm.prank(USER); // the next tx will be sent by USER making the USER EOA the new msg.sender
        fundMe.fund{ value: SEND_VALUE }();
        uint amountFunded = fundMe.getAddressToAmountFunded(USER);
        assertEq(amountFunded, SEND_VALUE);
    }

    modifier funded() {
        // this will help avoid rewriting the fund tx unecessarily
        vm.prank(USER);
        fundMe.fund{ value: SEND_VALUE }();
        _;
    }

    function testAddsFunderToFundersArray() public funded {
        address funder = fundMe.getFunder(0); // first and only funder i.e @ index 0
        assertEq(funder, USER);
    }

    function testOnlyOwnerCanWithdraw() public funded {
        // user is not the owner, msg.sender is the owner
        vm.expectRevert();
        vm.prank(USER); // this will be ignored by vm.expectRevert()
        fundMe.withdraw();
    }

    function testWithdrawWithSingleFunder() public funded {
        // remember we have already funded
        // Arrange
        // after funding but before withdrawal
        uint startingOwnerBalance = fundMe.getOwner().balance;
        uint startingFundMeBalance = address(fundMe).balance;

        // Act
        vm.prank(fundMe.getOwner());
        fundMe.withdraw();

        // Assert
        uint endingOwnerBalance = fundMe.getOwner().balance;
        uint endingFundMeBalance = address(fundMe).balance;
        assertEq(endingFundMeBalance, 0);
        assertEq(
            startingFundMeBalance + startingOwnerBalance,
            endingOwnerBalance
        ); // this only works because on avil chain gas price is 0, so our txs are not affected by gas
    }

    function testWithdrawForMultipleFunders() public funded {
        // Arrange
        uint160 numberOfFunders = 10;
        uint160 startingFunderIndex = 1;
        for (uint160 i = startingFunderIndex; i < numberOfFunders; i++) {
            // hoax cheat code: does a vm.prank + vm.deal for an address
            // to make addresses from number like address(0), we must use a uint160 as argument
            hoax(address(i), SEND_VALUE);
            // remember vm.prank is still in action, so address(i) calls the fund tx
            fundMe.fund{ value: SEND_VALUE }();
        }

        // after funding but before withdrawal
        uint startingOwnerBalance = fundMe.getOwner().balance;
        uint startingFundMeBalance = address(fundMe).balance;

        // Act
        uint gasStart = gasleft(); // how much gas we've got b4 this tx
        vm.txGasPrice(GAS_PRICE); // allowing this tx to be affected by gas
        vm.startPrank(fundMe.getOwner());
        fundMe.withdraw();
        vm.stopPrank();

        uint gasEnd = gasleft(); // how much gas we've got after the tx
        uint gasUsed = (gasStart - gasEnd) * tx.gasprice;
        console.log(gasUsed);

        // Assert
        assertEq(address(fundMe).balance, 0);
        assertEq(
            startingFundMeBalance + startingOwnerBalance,
            fundMe.getOwner().balance
        );
    }
}
