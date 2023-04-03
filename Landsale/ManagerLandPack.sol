// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./LandPack5.sol";
import "./LandPack10.sol";
import "./LandPack15.sol";

contract ManagerLandPack {
    using SafeMath for uint256;

    address payable public factoryBeneficiary;

    AggregatorV3Interface internal priceFeed;
    //false means ChainLink getLatestPrice. true means price set by owner
    bool public priceFlag = false;
    uint256 public ownerPrice = 0;

    uint256 public landPack5Price = 750;
    uint256 public landPack10Price = 1500;
    uint256 public landPack15Price = 2250;

    address public LandPack5Address;
    address public LandPack10Address;
    address public LandPack15Address;

    constructor(address payable _beneficiary) {
        factoryBeneficiary = _beneficiary;

       /**
        * Network: Binance Smart Chain
        * Aggregator: BNB/USD
        * Address: 0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE
        */
        priceFeed = AggregatorV3Interface(0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE);
    }

    function setLandPackAddress(address _LandPackAddress, uint256 packType) public {
      require(msg.sender == factoryBeneficiary, 'Only owner!');
      require(packType >= 0 && packType <= 2,'Invalid land pack');

      if(packType == 0) { //landPack5
        LandPack5Address = _LandPackAddress;
      } else if(packType == 1) { //landPack10
        LandPack10Address = _LandPackAddress;
      } else if(packType == 2) { //landPack15
        LandPack15Address = _LandPackAddress;
      }
    }

    function setLandPackPrice(uint256 _landPackPrice, uint256 packType) public {
      require(msg.sender == factoryBeneficiary, 'Only owner!');
      require(packType >= 0 && packType <= 2,'Invalid land pack');

      if(packType == 0) { //landPack5
        landPack5Price = _landPackPrice;
      } else if(packType == 1) { //landPack10
        landPack10Price = _landPackPrice;
      } else if(packType == 2) { //landPack15
        landPack15Price = _landPackPrice;
      }
    }

    function setOwnerPrice(uint256 _ownerPrice) public {
      require(msg.sender == factoryBeneficiary, 'Only owner!');

      if(_ownerPrice == 0 ) {
        ownerPrice = uint256(getLatestPrice());
        priceFlag = false;
      } else {
        ownerPrice = _ownerPrice;
        priceFlag = true;
      }
    }

    function checkAmount(uint256 value, uint256 landCount, uint256 packType) internal returns (bool) {

        if(!priceFlag) {
          ownerPrice = uint256(getLatestPrice());
        }

        require(ownerPrice > 1, 'Wrong bnb price!');

        uint256 price = 0;

        if(packType == 0) { //landPack5
          price = landPack5Price;
        } else if(packType == 1) { //landPack10
          price = landPack10Price;
        } else if(packType == 2) { //landPack15
          price = landPack15Price;
        }

        uint256 lowerPriceLimit = (landCount * price * 10 ** 18) / ownerPrice;

        if(value >= lowerPriceLimit) {
          return true;
        } else {
          return false;
        }
    }

    function awardNfts(uint256 landCount, uint256 packType) public payable {
      require(landCount > 0, 'Land number is 0');
      require(checkAmount(msg.value, landCount, packType), 'Not enough BNB sent!');

      for(uint i=0; i < landCount; i ++) {      
        if(packType == 0) { //landPack5
          LandPack5(LandPack5Address).awardNFT(factoryBeneficiary, msg.sender);
        } else if(packType == 1) { //landPack10
          LandPack10(LandPack10Address).awardNFT(factoryBeneficiary, msg.sender);
        } else if(packType == 2) { //landPack15
          LandPack15(LandPack15Address).awardNFT(factoryBeneficiary, msg.sender);
        }
      }

      uint256 balance = address(this).balance;
      (bool success, ) = payable(factoryBeneficiary).call{value:balance, gas: 3000000}('');
    }

    /**
     * Returns the latest price
     */
    function getLatestPrice() public view returns (uint256) {
        (
            uint80 roundID,
            int price,
            uint startedAt,
            uint timeStamp,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();
        return uint256(price).div(100000000);
    }

    function forwardFunds() external {
      require(msg.sender == factoryBeneficiary, 'Caller is not owner');

      uint256 balance = address(this).balance;
      (bool success, ) = payable(factoryBeneficiary).call{value:balance, gas: 3000000}('');
    }
}
