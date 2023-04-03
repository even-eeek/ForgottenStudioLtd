// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./Auction.sol";
import "./Land.sol";

contract BidFactory {
    using SafeMath for uint256;

    /* Auction[] public auctionArray; */
    int public totalAuctions = 0;
    address payable public factoryBeneficiary;

    AggregatorV3Interface internal priceFeed;

    uint256 public battleMinPriceAmount = 150;
    uint256 public villageMinPriceAmount = 1250;
    uint256 public cityMinPriceAmount = 10000;

    //land type (0 battle, 1 village, 2 city) for each landId
    mapping(uint256 => uint256) public landType;
    //Auction for each landId
    mapping(uint256 => Auction) public auctionMapping;

    address public LandAddress;

    //false means ChainLink getLatestPrice. true means price set by owner
    bool public priceFlag = false;
    uint256 public ownerPrice = 0;

    event BidFactoryError(string message, uint256 value);

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

    function setLandPrice(uint256 _price, uint256 _landType) public {
      require(msg.sender == factoryBeneficiary, 'Only owner!');
      require(_landType >= 0 && _landType <= 2, 'Invalid land!');

      if(_landType == 0) { 
        //battle 
        battleMinPriceAmount = _price;
      } else if(_landType == 1) { 
        //village 
        villageMinPriceAmount = _price;
      } else if(_landType == 2) { 
        //city 
        cityMinPriceAmount = _price;
      } 
    }

    function factoryCheckAuctionStarted(uint256 _landId) external view returns (bool) {
        Auction auction = getAuctionFromLandId(_landId);

        return  auction.checkAuctionStarted();
    }

    function factoryGetTotalAuctions() external view returns (int) {
        return totalAuctions;
    }

    function setLandAddress(address _LandAddress) public {
      require(msg.sender == factoryBeneficiary, 'Only owner!');
      LandAddress = _LandAddress;
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

    function contractBalance(uint256 _landId) public view returns(uint) {
      Auction auction = getAuctionFromLandId(_landId);
      return address(auction).balance;
    }

    function createAuctionContract(uint _biddingTime, uint256 _landId, uint256 _landType) public {
        require(address(auctionMapping[_landId]) == address(0), 'Auction already created');

        Auction auction = new Auction(_biddingTime, factoryBeneficiary);
        auctionMapping[_landId] = auction;
        landType[_landId] = _landType;
        totalAuctions += 1;
    }

    function getAuctionFromLandId(uint256 _landId) internal view returns (Auction) {
      return auctionMapping[_landId];
    }

    function checkAmount(uint256 value, uint256 highestBid, uint256 _landId) internal returns (bool) {
      if(highestBid > 0) {
        if(value > highestBid) {
          return true;
        } else {
          return false;
        }
      } else {
          uint256 landPrice = returnLandPrice(_landId);

          if(!priceFlag) {
            ownerPrice = uint256(getLatestPrice());
          }

          require(ownerPrice > 1, 'Wrong bnb price!');

          uint256 lowerPriceLimit = (landPrice * 10 ** 18) / ownerPrice;

          if(value > (lowerPriceLimit)) {
            return true;
          } else {
            return false;
          }
      }
    }

    function factoryBid(uint256 _landId) public payable {
      require(address(auctionMapping[_landId]) != address(0), 'Auction does not exist!');

      Auction auction = getAuctionFromLandId(_landId);
      require(auction.ended() == false, 'Contract claimed');

      if(auction.auctionEndTime() > 0) {
        require(auction.timeRemaining() > 0, 'Auction ended');
      }

      address highestBidder = auction.getHighestBidder();
      require(msg.sender != highestBidder, 'Caller is already highest bidder');

      uint256 userContribution = auction.getUserPendingAmount(msg.sender);
      uint256 highestBid = auction.getHighestBid();
      require(checkAmount(userContribution + msg.value, highestBid, _landId), 'Bid not big enough!');

      bytes memory data = abi.encode(msg.sender);
      (bool success, ) = payable(auction).call{value:msg.value, gas: 3000000}(data);
    }

    function factoryGetUserPendingAmount(uint256 _landId) external view returns (uint256) {
      Auction auction = getAuctionFromLandId(_landId);
      return  auction.getUserPendingAmount(msg.sender);
    }

    function factoryGetHighestBidder(uint256 _landId) external view returns (address) {
      Auction auction = getAuctionFromLandId(_landId);
      return  auction.getHighestBidder();
    }

    function factoryGetHighestBid(uint256 _landId) public view returns (uint256) {
      Auction auction = getAuctionFromLandId(_landId);
      return  auction.getHighestBid();
    }

    function factoryGetBidders(uint256 _landId) external view returns (Auction.Bid[] memory) {
      Auction auction = getAuctionFromLandId(_landId);
      return  auction.getBidders();
    }

    function factoryWithdrawal(uint256 _landId) public payable returns(bool) {
      Auction auction = getAuctionFromLandId(_landId);
      return auction.withdrawal(payable(msg.sender));
    }

    function factoryCheckClaimed(uint256 _landId) public view returns (bool) {
      Auction auction = getAuctionFromLandId(_landId);
      return auction.ended();
    }

    function Claim(uint256 _landId) public payable {
        require(!factoryCheckClaimed(_landId), 'Already Claimed!');

        Auction auction = getAuctionFromLandId(_landId);
        address winner = auction.Claim(payable(msg.sender));
        if(winner != address(0)) {
          transferClaimedLand(winner, _landId);
        }
    }

    function factoryTimeRemaining(uint256 _landId) public view returns (uint256) {
      Auction auction = getAuctionFromLandId(_landId);
      return auction.timeRemaining();
    }

    function transferClaimedLand(address winner, uint256 _landId) internal{
       uint256 land_type = landType[_landId];

       Land(LandAddress).transferFrom(factoryBeneficiary, winner, _landId);
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

    function returnLandPrice(uint256 _landId) internal returns (uint256) {
      uint256 land_type = landType[_landId];

      if(land_type == 0) {
        return battleMinPriceAmount;
      } else if(land_type == 1) {
        return villageMinPriceAmount;
      } else if(land_type == 2) {
        return cityMinPriceAmount;
      } else {
        return 1;
      }
    }

    function factoryForwardFunds(uint256 _landId) external {
      require(msg.sender == factoryBeneficiary, 'Caller is not owner');

      Auction auction = getAuctionFromLandId(_landId);
      return auction.auctionForwardFunds(msg.sender);
    }

    function forwardFunds() external {
      require(msg.sender == factoryBeneficiary, 'Caller is not owner');

      uint256 balance = address(this).balance;
      (bool success, ) = payable(factoryBeneficiary).call{value:balance, gas: 3000000}('');
    }
}
