// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "./Avatar.sol";

contract AvatarManager is IERC721Receiver, Pausable, Ownable{
    using SafeMath for uint256;

    address payable public factoryBeneficiary;
    address public NFTAddress;
    address public Aggregator;

    AggregatorV3Interface internal priceFeed;
    //false means ChainLink getLatestPrice. true means price set by owner
    bool public priceFlag = false;
    uint256 public ownerPrice = 0;

    uint256 public smallPrice = 5; 
    uint256 public mediumPrice = 10; 
    uint256 public largePrice = 25; 
    uint256 public exclusivePrice = 50; 

    // Mapping approvedContracts address
    mapping(address => bool) private approvedContracts;

    constructor(address payable _beneficiary) {
        factoryBeneficiary = _beneficiary;

       /**
        * Network: Binance Smart Chain
        * Aggregator: BNB/USD
        * Address: 0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE
        */
        Aggregator = 0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE;
        priceFeed = AggregatorV3Interface(0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE);
    }

    function onERC721Received(address, address, uint256, bytes memory) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function setAggregatorV3Interface(address _Aggregator) public onlyOwner {
        Aggregator = _Aggregator;
        priceFeed = AggregatorV3Interface(Aggregator);
    }

    /**
     * @dev Pause crowdsale only by owner
     */
    function pause() public ownerOrApprovedByOwner {
        _pause();
    }

    /**
     * @dev Unpause crowdsale only by owner
     */
    function unpause() public ownerOrApprovedByOwner {
        _unpause();
    }

    /**
     * @dev _approvedRemoveContracts `to` to false
     *
     */
    function _approvedRemoveContracts(address to) public onlyOwner {
        approvedContracts[to] = false;
    }
	
	/**
     * @dev approvedContracts `to` to true
     *
     */
    function _approvedContracts(address to) public onlyOwner {
        approvedContracts[to] = true;
    }

    /**
     * @dev _getApprovedContracts
     *
     */
    function _getApprovedContracts(address to) public view  returns (bool)  {
        return approvedContracts[to];
    }

    modifier ownerOrApprovedByOwner {
        require(msg.sender == owner() || _getApprovedContracts(msg.sender), 'Not owner nor approved by owner');
        _;
    }

    function setBeneficiaryAddress(address payable _factoryBeneficiary) public onlyOwner {
      factoryBeneficiary = _factoryBeneficiary;
    }

    function setNFTAddress(address _NFTAddress) public ownerOrApprovedByOwner {
      NFTAddress = _NFTAddress;
    }

    function setNftPrice(uint256 _price, uint256 rarity) public ownerOrApprovedByOwner {
      require(rarity >= 0 && rarity <= 3, 'wrong type');

      if(rarity == 0) {
        smallPrice = _price; 
      } else if(rarity == 1) {
        mediumPrice = _price; 
      } else if(rarity == 2) {
        largePrice = _price; 
      } else if(rarity == 3) {
        exclusivePrice = _price; 
      }
    }

    function setOwnerPrice(uint256 _ownerPrice) public ownerOrApprovedByOwner {

      if(_ownerPrice == 0 ) {
        ownerPrice = uint256(getLatestPrice());
        priceFlag = false;
      } else {
        ownerPrice = _ownerPrice;
        priceFlag = true;
      }
    }

    function checkAmount(uint256 value, uint256 nftCount, uint256 rarity) internal returns (bool) {
      require(rarity >= 0 && rarity <= 3, 'Wrong avatar type!');

        if(!priceFlag) {
          ownerPrice = uint256(getLatestPrice());
        }

        require(ownerPrice > 1, 'Wrong bnb price!');

        uint256 nftPrice = smallPrice;

        if(rarity == 0) {
          nftPrice = smallPrice; 
        } else if(rarity == 1) {
          nftPrice = mediumPrice;
        } else if(rarity == 2) {
          nftPrice = largePrice;
        } else if(rarity == 3) {
          nftPrice = exclusivePrice;
        }

        uint256 lowerPriceLimit = (nftCount * nftPrice * 1000000000000000000) / ownerPrice;

        if(value >= lowerPriceLimit) {
          return true;
        } else {
          return false;
        }
    }

    function airdropERC721(address[] calldata _to, uint256[] calldata _id) public ownerOrApprovedByOwner whenNotPaused {
        require(_to.length == _id.length, "Receivers and IDs are different length");
        for (uint256 i = 0; i < _to.length; i++) {
            Avatar(NFTAddress).safeTransferFrom(address(this), _to[i], _id[i]);
        }
    }

    function awardNfts(uint256 nftCount, uint256 nftId, uint256 rarity) public payable {
      require(nftCount > 0, 'nft count is 0');
      require(rarity >= 0 && rarity <= 3, 'wrong type');
      require(checkAmount(msg.value, nftCount, rarity), 'Not enough BNB sent!');

      uint256 loopLength = 2;
      uint256 borders = 1;
      uint256 borderBool = 1;

      if(rarity == 0) {
        loopLength = 2; 
        borders = 1;
      } else if(rarity == 1) {
        loopLength = 5;
        borders = 2;
      } else if(rarity == 2) {
        loopLength = 10;
        borders = 5;
      } else if(rarity == 3) {
        loopLength = 5;
        borders = 1;
      }

      for(uint i=0; i < nftCount; i ++) {
        for(uint j=0; j < loopLength; j ++) {
          if(j > borders - 1) {
            borderBool = 0;
          }
		      Avatar(NFTAddress).awardNFT(address(this), msg.sender, nftId, borderBool);
        }
      }

      uint256 balance = address(this).balance;
      (bool success, ) = payable(factoryBeneficiary).call{value:balance, gas: 3000000}('');
    }

    function sendNftIdAndRarity(address _to, uint256 _id, uint256 nftId, uint256 rarity) public ownerOrApprovedByOwner whenNotPaused {
        bytes memory data = abi.encode(nftId, rarity);

        Avatar(NFTAddress).safeTransferFrom(address(this), _to, _id, data);
    }

    function sendNft(address _to, uint256 _id) public ownerOrApprovedByOwner whenNotPaused {
        Avatar(NFTAddress).safeTransferFrom(address(this), _to, _id);
    }

    function mintNft(address _to, uint256 nftType, uint256 rarity) public ownerOrApprovedByOwner whenNotPaused {
        Avatar(NFTAddress).awardNFT(address(this), _to, nftType, rarity);
    }

    /**
     * Returns the latest price
     */
    function getLatestPrice() public view returns (uint256) {
        require(Aggregator != address(0), 'Price Aggregator not set!');
        (
            ,
            int price,
            ,
            ,
            
        ) = priceFeed.latestRoundData();
        return uint256(price).div(100000000);
    }

    function forwardFunds() external ownerOrApprovedByOwner {

      uint256 balance = address(this).balance;
      (bool success, ) = payable(factoryBeneficiary).call{value:balance, gas: 3000000}('');
    }
}
