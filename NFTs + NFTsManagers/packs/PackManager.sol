// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../characters/CharManager.sol";
import "../pets/PetManager.sol";
import "../mounts/MountManager.sol";
import "../equipments/EquipmentManager.sol";

contract PackManager is Pausable, Ownable {
    using SafeMath for uint256;

    address payable public factoryBeneficiary;

    AggregatorV3Interface internal priceFeed;
    //false means ChainLink getLatestPrice. true means price set by owner
    bool public priceFlag = false;
    uint256 public ownerPrice = 0;
    
    address public Aggregator;

    address public charManagerAddress;
    address public mountManagerAddress;
    address public petManagerAddress;
    address public equipmentManagerAddress;

    //25% discount
    uint256 public nftPrice = 100; 
    
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

    function setManagerAddress(address _ManagerAddress, uint256 _nftType) public ownerOrApprovedByOwner {
      require(_nftType >= 0 && _nftType <= 3, 'Invalid Type!');

      if(_nftType == 0) { 
        charManagerAddress = _ManagerAddress;
      } else if(_nftType == 1) { 
        mountManagerAddress = _ManagerAddress;
      } else if(_nftType == 2) { 
        petManagerAddress = _ManagerAddress;
      } else if(_nftType == 3) { 
        equipmentManagerAddress = _ManagerAddress;
      } 
    }

    function setNftPrice(uint256 _price) public ownerOrApprovedByOwner {
      nftPrice = _price;
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

    function checkAmount(uint256 value, uint256 nftCount) internal returns (bool) {

        if(!priceFlag) {
          ownerPrice = uint256(getLatestPrice());
        }

        require(ownerPrice > 1, 'Wrong bnb price!');

        uint256 lowerPriceLimit = (nftCount * nftPrice * 1000000000000000000) / ownerPrice;

        if(value >= lowerPriceLimit) {
          return true;
        } else {
          return false;
        }
    }

    function awardNfts(uint256 nftCount, uint256 nftId, uint256 rarity) public payable {
      require(nftCount > 0, 'nft count is 0');
      require(checkAmount(msg.value, nftCount), 'Not enough BNB sent!');

      for(uint i=0; i < nftCount; i ++) {
        CharManager(charManagerAddress).mintNft(msg.sender, nftId, rarity);
        MountManager(mountManagerAddress).mintNft(msg.sender, nftId, rarity);
        PetManager(petManagerAddress).mintNft(msg.sender, nftId, rarity);
        EquipmentManager(equipmentManagerAddress).mintNft(msg.sender, nftId, rarity);
      }

      uint256 balance = address(this).balance;
      (bool success, ) = payable(factoryBeneficiary).call{value:balance, gas: 3000000}('');
    }

    function sendNfts(address to, uint256 nftCount, uint256 nftId, uint256 rarity) public payable ownerOrApprovedByOwner {
      require(nftCount > 0, 'nft count is 0');

      for(uint i=0; i < nftCount; i ++) {
        CharManager(charManagerAddress).mintNft(to, nftId, rarity);
        MountManager(mountManagerAddress).mintNft(to, nftId, rarity);
        PetManager(petManagerAddress).mintNft(to, nftId, rarity);
        EquipmentManager(equipmentManagerAddress).mintNft(to, nftId, rarity);
      }

      uint256 balance = address(this).balance;
      (bool success, ) = payable(factoryBeneficiary).call{value:balance, gas: 3000000}('');
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
