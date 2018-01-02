pragma solidity ^0.4.17;


/**
 * @title Ownable
 * Provides basic authorization control
 */

contract Ownable {
	address public owner;

	function Ownable() {
		owner = msg.sender;
	}

	modifier onlyOwner() { 
		require(msg.sender == owner);
		_;
	}
	
	function transferOwnership(address newOwner) onlyOwner {
		if (newOwner != address(0)) owner = newOwner;
	}
}


/**
 * @title PlanetAccessControl
 * Provides boss control, contract pause and unpause 
 */

contract PlanetAccessControl {
	address public bossAddress;

	bool public paused = false;

	event ContractUpgrade(address newContract);
	
	modifier onlyBoss() { 
		require(msg.sender == bossAddress);
		_; 
	}
	
	function setBoss(address newBoss) external onlyBoss {
		require(newBoss != address(0));
		bossAddress = newBoss;
	}

	modifier whenNotPaused() {
		require(!paused);
		_;
	}

	modifier whenPaused() {
		require(paused);
		_;
	}

	function pause() external onlyBoss whenNotPaused {
		paused = true;
	}

	function unpause() external onlyBoss whenPaused {
		paused = false;
	}
}

contract PlanetBase is PlanetAccessControl {
	
}