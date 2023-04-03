// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./Land.sol";

import "./LandPack5.sol";
import "./LandPack10.sol";
import "./LandPack15.sol";

contract ManagerLand {
    using SafeMath for uint256;

    address payable public factoryBeneficiary;

    AggregatorV3Interface internal priceFeed;
    //false means ChainLink getLatestPrice. true means price set by owner
    bool public priceFlag = false;
    uint256 public ownerPrice = 0;

    uint256 public landPrice = 150;
    address public LandAddress;

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
        /* priceFeed = AggregatorV3Interface(0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE); //mainnet */
        priceFeed = AggregatorV3Interface(0x2514895c72f50D8bd4B4F9b1110F0D6bD2c97526); //testnet
    }

    function setLandAddress(address _LandAddress) public {
      require(msg.sender == factoryBeneficiary, 'Only owner!');
      LandAddress = _LandAddress;
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

    function setLandPrice(uint256 _landPrice) public {
      require(msg.sender == factoryBeneficiary, 'Only owner!');
      landPrice = _landPrice;
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

    function checkAmount(uint256 value, uint256 landCount) internal returns (bool) {

          if(!priceFlag) {
          ownerPrice = uint256(getLatestPrice());
        }

        require(ownerPrice > 1, 'Wrong bnb price!');

        uint256 lowerPriceLimit = (landCount * landPrice * 10 ** 18) / ownerPrice;

        if(value >= lowerPriceLimit) {
          return true;
        } else {
          return false;
        }
    }

    function buyLands(uint256[] memory landList, uint256 landCount, uint256 packType) public payable {
      require(landCount > 0, 'Land number is 0');
      require(packType >= 0 && packType <= 3, 'Invalid landPack');
      if(packType == 3) { //3 means no landPack
        require(checkAmount(msg.value, landCount), 'Not enough BNB sent!');

        executeTransferLand(landList, landCount);
        
        uint256 balance = address(this).balance;
        (bool success, ) = payable(factoryBeneficiary).call{value:balance, gas: 3000000}('');
      } else {
        if(packType == 0) {
          require(landCount == 5, 'LandPack5 only works for 5 lands');
          uint256 balanceLandPack5 = LandPack5(LandPack5Address).balanceOf(msg.sender);
          require(balanceLandPack5 > 0, 'No landPack5 available in balance');
          uint256 lastLandPack5Token = LandPack5(LandPack5Address).getAddressLastToken(msg.sender);

          executeTransferLand(landList, landCount);

          LandPack5(LandPack5Address).transferFrom(msg.sender, factoryBeneficiary, lastLandPack5Token);

        } else if(packType == 1) {
          require(landCount == 10, 'LandPack10 only works for 10 lands');
          uint256 balanceLandPack10 = LandPack10(LandPack10Address).balanceOf(msg.sender);
          require(balanceLandPack10 > 0, 'No landPack10 available in balance');
          uint256 lastLandPack10Token = LandPack10(LandPack10Address).getAddressLastToken(msg.sender);

          executeTransferLand(landList, landCount);

          LandPack10(LandPack10Address).transferFrom(msg.sender, factoryBeneficiary, lastLandPack10Token);

        } else if(packType == 2) {
          require(landCount == 15, 'LandPack15 only works for 15 lands');
          uint256 balanceLandPack15 = LandPack15(LandPack15Address).balanceOf(msg.sender);
          require(balanceLandPack15 > 0, 'No landPack15 available in balance');
          uint256 lastLandPack15Token = LandPack15(LandPack15Address).getAddressLastToken(msg.sender);

          executeTransferLand(landList, landCount);

          LandPack15(LandPack15Address).transferFrom(msg.sender, factoryBeneficiary, lastLandPack15Token);

        }
      }
    }

    function executeTransferLand(uint256[] memory landList, uint256 landCount) internal {
      for(uint i=0; i < landCount; i ++) {
        uint256 landId = landList[i];
        Land(LandAddress).transferFrom(factoryBeneficiary, msg.sender, landId);
      }
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
