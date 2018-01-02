pragma solidity ^0.4.17;


contract ERC721 {
    // Required methods
    function totalSupply() public view returns (uint256 total);
    function balanceOf(address _owner) public view returns (uint256 balance);
    function ownerOf(uint256 _tokenId) external view returns (address owner);
    function approve(address _to, uint256 _tokenId) external;
    function transfer(address _to, uint256 _tokenId) external;
    function transferFrom(address _from, address _to, uint256 _tokenId) external;

    // Events
    event Transfer(address from, address to, uint256 tokenId);
    event Approval(address owner, address approved, uint256 tokenId);

    // Optional
    // function name() public view returns (string name);
    // function symbol() public view returns (string symbol);
    // function tokensOfOwner(address _owner) external view returns (uint256[] tokenIds);

    // ERC-165 Compatibility (https://github.com/ethereum/EIPs/issues/165)
    function supportsInterface(bytes4 _interfaceID) external view returns (bool);
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
	
	function setBoss(address _newBoss) external onlyBoss {
		require(_newBoss != address(0));
		bossAddress = _newBoss;
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

	function unpause() public onlyBoss whenPaused {
		paused = false;
	}
}


/**
 * @title PlanetBase
 * Base strcut of Planet, waitting to add more 
 */

contract PlanetBase is PlanetAccessControl {
	event Discover(address owner, uint256 planetId);
	event Transfer(address from, address to, uint256 tokenId);

	struct Planet {
		uint64 discoverTime;
	}

	SaleClockAuction public saleAuction;

	Planet[] planets;
	mapping (uint256 => address) public planetIndexToOwner;
	mapping (address => uint256) public ownershipPlanetCount;
	mapping (uint256 => address) public planetIndexToApproved;
	
	function _transfer(address _from, address _to, uint256 _tokenId) internal {
		++ownershipPlanetCount[_to];
		planetIndexToOwner[_tokenId] = _to;
		if (_from != address(0)) {
			--ownershipPlanetCount[_from];
			delete planetIndexToApproved[_from];
		}

		Transfer(_from, _to, _tokenId);
	}

	function _discoverPlanet(address _owner) internal returns(uint256) {
		Planet memory _planet = Planet({ discoverTime: uint64(now) });
		uint256 newPlanetId = planets.push(_planet) - 1;

		Discover(_owner, newPlanetId);
		_transfer(0, _owner, newPlanetId);

		return newPlanetId;
	}
}


/**
 * @title PlanetOwnership
 * Manage planet ownership 
 */

contract PlanetOwnership is PlanetBase, ERC721 {
	string public constant name = "CryptoPlanet";
	string public constant symbol = "CP";

	bytes4 constant InterfaceSignature_ERC165 =
        bytes4(keccak256('supportsInterface(bytes4)'));

    bytes4 constant InterfaceSignature_ERC721 =
        bytes4(keccak256('name()')) ^
        bytes4(keccak256('symbol()')) ^
        bytes4(keccak256('totalSupply()')) ^
        bytes4(keccak256('balanceOf(address)')) ^
        bytes4(keccak256('ownerOf(uint256)')) ^
        bytes4(keccak256('approve(address,uint256)')) ^
        bytes4(keccak256('transfer(address,uint256)')) ^
        bytes4(keccak256('transferFrom(address,address,uint256)')) ^
        bytes4(keccak256('tokensOfOwner(address)'));

    function supportsInterface(bytes4 _interfaceID) external view returns (bool) {
        return ((_interfaceID == InterfaceSignature_ERC165) || (_interfaceID == InterfaceSignature_ERC721));
    }

	function _owns(address _claimant, uint256 _tokenId) internal view returns (bool) {
		return planetIndexToOwner[_tokenId] == _claimant;
	}

	function _approvedFor(address _claimant, uint256 _tokenId) internal view returns (bool) {
		return planetIndexToApproved[_tokenId] == _claimant;
	}

	function _approve(uint256 _tokenId, address _approved) internal {
		planetIndexToApproved[_tokenId] = _approved;
	}

	function balanceOf(address _owner) public view returns (uint256) {
		return ownershipPlanetCount[_owner];
	}

	function transfer(address _to, uint256 _tokenId) external whenNotPaused {
		require(_to != address(0));
		require(_to != address(this));
		require(_to != address(saleAuction));
		require(_owns(msg.sender, _tokenId));

		_transfer(msg.sender, _to, _tokenId);
	}

	function approve(address _to, uint256 _tokenId) external whenNotPaused {
		require(_owns(msg.sender, _tokenId));
		_approve(_tokenId, _to);
		Approval(msg.sender, _to, _tokenId);
	}

	function transferFrom(address _from, address _to, uint256 _tokenId) external whenNotPaused {
		require(_to != address(0));
		require(_to != address(this));
		require(_approvedFor(msg.sender, _tokenId));
		require(_owns(_from, _tokenId));

		_transfer(_from, _to, _tokenId);
	}

	function totalSupply() public view returns (uint256) {
		return planets.length - 1;	// palnet id start from 1
	}

	function ownerOf(uint256 _tokenId) external view returns (address owner) {
		owner = planetIndexToOwner[_tokenId];
		require(owner != address(0));
	}

	function tokensOfOwner(address _owner) external view returns (uint256[]) {
		uint256 cnt = balanceOf(_owner);
		if (cnt == 0) {
			return new uint256[](0);
		} else {
			uint256[] memory result = new uint256[](cnt);
			uint256 totalPlanets = totalSupply();
			uint256 resultIdx = 0;
			uint256 pId;
			for (pId = 1; pId <= totalPlanets; ++pId) {
				if (planetIndexToOwner[pId] == owner) {
					result[resultIdx] = pId;
					++resultIdx;
				}
			}

			return result;
		}
	}
}


/**
 * @title ClockAuctionBase
 * Base contract of clock auction 
 */

contract ClockAuctionBase {
	struct Auction {
		address seller;
		uint128 startingPrice;
		uint128 endingPrice;
		uint64 duration;
		uint64 startedAt;
	}

	ERC721 public nonFungibleContract;
	uint256 public ownerCut;
	mapping (uint256 => Auction) tokenIdToAuction;
	
	event AuctionCreated(uint256 tokenId, uint256 startingPrice, uint256 endingPrice, uint256 duration);
    event AuctionSuccessful(uint256 tokenId, uint256 totalPrice, address winner);
    event AuctionCancelled(uint256 tokenId);

    function _owns(address _claimant, uint256 _tokenId) internal view returns (bool) {
    	return nonFungibleContract.ownerOf(_tokenId) == _claimant;
    }

    function _escrow(address _owner, uint256 _tokenId) internal {
    	nonFungibleContract.transferFrom(_owner, this, _tokenId);
    }

    function _transfer(address _receiver, uint256 _tokenId) internal {
    	nonFungibleContract.transfer(_receiver, _token);
    }

    function _addAuction(uint256 _tokenId, Auction _auction) internal {
    	require(_auction.duration >= 1 minutes);
    	tokenIdToAuction[_tokenId] = _auction;
    	AuctionCreated(
            uint256(_tokenId),
            uint256(_auction.startingPrice),
            uint256(_auction.endingPrice),
            uint256(_auction.duration)
        );
    }

    function _removeAuction(uint256 _tokenId) internal {
    	delete tokenIdToAuction[_tokenId];
    }

    function _cancelAuction(uint256 _tokenId, address _seller) internal {
    	_removeAuction(_tokenId);
    	_transfer(_seller, _tokenId);
    	AuctionCancelled(_tokenId);
    }

    function _isOnAuction(Auction storage _auction) internal view returns (bool) {
    	return _auction.startedAt > 0;
    }

    function _computeCurrentPrice(
        uint256 _startingPrice,
        uint256 _endingPrice,
        uint256 _duration,
        uint256 _secondsPassed
    ) internal pure returns (uint256) {
    	if (_secondsPassed >= _duration) {
    		return _endingPrice;
    	} else {
    		int256 totalPriceChange = int256(_endingPrice) - int256(_startingPrice);
            int256 currentPriceChange = totalPriceChange * int256(_secondsPassed) / int256(_duration);
            int256 currentPrice = int256(_startingPrice) + currentPriceChange;

            return uint256(currentPrice);
    	}
    }

    function _computeCut(uint256 _price) internal view returns (uint256) {
    	return _price * ownerCut / 10000;
    }

    function _currentPrice(Auction storage _auction) internal view returns (uint256) {
    	uint256 secondsPassed = 0;
    	if (secondsPassed > _auction.startedAt) {
    		secondsPassed = now - _auction.startedAt;
    	}

    	return _computeCurrentPrice(
    		_auction.startingPrice,
    		_auction.endingPrice,
    		_auction.duration,
    		secondsPassed
    	);
    }

    function _bid(uint256 _tokenId, uint256 _bidAmount) internal returns (uint256) {
    	Auction storage auction = tokenIdToAuction[_tokenId];
    	require(_isOnAuction(auction));
    	uint256 price = _currentPrice(auction);
    	require(_bidAmount >= price);

    	address seller = auction.seller;
    	_removeAuction(_tokenId);

    	if (price > 0) {
    		uint256 auctioneerCut = _computeCut(price);
    		uint256 sellerProceeds = price - auctioneerCut;
    		seller.transfer(sellerProceeds);
    	}

    	uint256 bidExcess = _bidAmount - price;
    	msg.sender.transfer(bidExcess);

    	AuctionSuccessful(_tokenId, price, msg.sender);

    	returns price;
    }
}


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
 * @title Pausable
 * Base contract which allows children to implement an emergency stop mechanism.
 */
 
contract Pausable is Ownable {
  event Pause();
  event Unpause();

  bool public paused = false;

  modifier whenNotPaused() {
    require(!paused);
    _;
  }

  modifier whenPaused {
    require(paused);
    _;
  }

  function pause() onlyOwner whenNotPaused returns (bool) {
    paused = true;
    Pause();
    return true;
  }

  function unpause() onlyOwner whenPaused returns (bool) {
    paused = false;
    Unpause();
    return true;
  }
}


contract ClockAuction is Pausable, ClockAuctionBase {

    /// @dev The ERC-165 interface signature for ERC-721.
    ///  Ref: https://github.com/ethereum/EIPs/issues/165
    ///  Ref: https://github.com/ethereum/EIPs/issues/721
    bytes4 constant InterfaceSignature_ERC721 = bytes4(0x9f40b779);

    /// @dev Constructor creates a reference to the NFT ownership contract
    ///  and verifies the owner cut is in the valid range.
    /// @param _nftAddress - address of a deployed contract implementing
    ///  the Nonfungible Interface.
    /// @param _cut - percent cut the owner takes on each auction, must be
    ///  between 0-10,000.
    function ClockAuction(address _nftAddress, uint256 _cut) public {
        require(_cut <= 10000);
        ownerCut = _cut;

        ERC721 candidateContract = ERC721(_nftAddress);
        require(candidateContract.supportsInterface(InterfaceSignature_ERC721));
        nonFungibleContract = candidateContract;
    }

    /// @dev Remove all Ether from the contract, which is the owner's cuts
    ///  as well as any Ether sent directly to the contract address.
    ///  Always transfers to the NFT contract, but can be called either by
    ///  the owner or the NFT contract.
    function withdrawBalance() external {
        address nftAddress = address(nonFungibleContract);

        require(
            msg.sender == owner ||
            msg.sender == nftAddress
        );
        // We are using this boolean method to make sure that even if one fails it will still work
        bool res = nftAddress.send(this.balance);
    }

    /// @dev Creates and begins a new auction.
    /// @param _tokenId - ID of token to auction, sender must be owner.
    /// @param _startingPrice - Price of item (in wei) at beginning of auction.
    /// @param _endingPrice - Price of item (in wei) at end of auction.
    /// @param _duration - Length of time to move between starting
    ///  price and ending price (in seconds).
    /// @param _seller - Seller, if not the message sender
    function createAuction(
        uint256 _tokenId,
        uint256 _startingPrice,
        uint256 _endingPrice,
        uint256 _duration,
        address _seller
    )
        external
        whenNotPaused
    {
        // Sanity check that no inputs overflow how many bits we've allocated
        // to store them in the auction struct.
        require(_startingPrice == uint256(uint128(_startingPrice)));
        require(_endingPrice == uint256(uint128(_endingPrice)));
        require(_duration == uint256(uint64(_duration)));

        require(_owns(msg.sender, _tokenId));
        _escrow(msg.sender, _tokenId);
        Auction memory auction = Auction(
            _seller,
            uint128(_startingPrice),
            uint128(_endingPrice),
            uint64(_duration),
            uint64(now)
        );
        _addAuction(_tokenId, auction);
    }

    /// @dev Bids on an open auction, completing the auction and transferring
    ///  ownership of the NFT if enough Ether is supplied.
    /// @param _tokenId - ID of token to bid on.
    function bid(uint256 _tokenId)
        external
        payable
        whenNotPaused
    {
        // _bid will throw if the bid or funds transfer fails
        _bid(_tokenId, msg.value);
        _transfer(msg.sender, _tokenId);
    }

    /// @dev Cancels an auction that hasn't been won yet.
    ///  Returns the NFT to original owner.
    /// @notice This is a state-modifying function that can
    ///  be called while the contract is paused.
    /// @param _tokenId - ID of token on auction
    function cancelAuction(uint256 _tokenId)
        external
    {
        Auction storage auction = tokenIdToAuction[_tokenId];
        require(_isOnAuction(auction));
        address seller = auction.seller;
        require(msg.sender == seller);
        _cancelAuction(_tokenId, seller);
    }

    /// @dev Cancels an auction when the contract is paused.
    ///  Only the owner may do this, and NFTs are returned to
    ///  the seller. This should only be used in emergencies.
    /// @param _tokenId - ID of the NFT on auction to cancel.
    function cancelAuctionWhenPaused(uint256 _tokenId)
        whenPaused
        onlyOwner
        external
    {
        Auction storage auction = tokenIdToAuction[_tokenId];
        require(_isOnAuction(auction));
        _cancelAuction(_tokenId, auction.seller);
    }

    /// @dev Returns auction info for an NFT on auction.
    /// @param _tokenId - ID of NFT on auction.
    function getAuction(uint256 _tokenId)
        external
        view
        returns
    (
        address seller,
        uint256 startingPrice,
        uint256 endingPrice,
        uint256 duration,
        uint256 startedAt
    ) {
        Auction storage auction = tokenIdToAuction[_tokenId];
        require(_isOnAuction(auction));
        return (
            auction.seller,
            auction.startingPrice,
            auction.endingPrice,
            auction.duration,
            auction.startedAt
        );
    }

    /// @dev Returns the current price of an auction.
    /// @param _tokenId - ID of the token price we are checking.
    function getCurrentPrice(uint256 _tokenId)
        external
        view
        returns (uint256)
    {
        Auction storage auction = tokenIdToAuction[_tokenId];
        require(_isOnAuction(auction));
        return _currentPrice(auction);
    }

}

contract SaleClockAuction {

}