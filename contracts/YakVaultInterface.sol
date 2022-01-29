// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface YakVaultInterface{
	function deposit(address token, uint amount) external;
	function withdraw(uint amount) external;
}