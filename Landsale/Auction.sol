// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Auction {

    struct Bid {
        address bidder;
        uint256 amount;
        uint256 timestamp;
    }

    Bid[] bidders;
    address public highestBidder;
    uint256 public highestBid = 0;

    address payable public beneficiary;
    uint256 public auctionEndTime = 0;
    uint256 public biddingTime = 0;
    bool public ended = false;
    mapping(address => uint256) public pendingReturns;

    event ReceivedAmount(address bidder, uint256 amount);
    event HighestBidIncrease(address bidder, uint256 amount);
    event Withdrawal(address bidder, uint256 amount);
    event ClaimHighestBidder(address winner, uint256 amount);
    event ErrorWithdrawal(address caller, string message);

    constructor(uint256 _biddingTime, address payable _beneficiary) {
        beneficiary = _beneficiary;
        biddingTime = _biddingTime;
    }

    function checkAuctionStarted() public view returns(bool) {
        if(auctionEndTime == 0) {
            return false;
        }
        return true;
    }

    function getBidders() public view returns (Bid[] memory) {
        Bid[] memory bidderList = bidders;
        return bidderList;
    }

    function getHighestBidder() public view returns (address) {
        return highestBidder;
    }

    function getHighestBid() public view returns (uint256) {
        return highestBid;
    }

    function getUserPendingAmount(address user) public view returns (uint256) {
        return pendingReturns[user];
    }

    function bid(address payable user, uint256 value) public payable  {
        require(user != highestBidder, 'Caller is already highest bidder');
        
        uint256 userContribution = pendingReturns[user];
        require(userContribution + value > highestBid, 'There is already a higher bid');

        if(auctionEndTime > 0) {
          require(block.timestamp < auctionEndTime, 'Auction has Ended!');
        } else {
          auctionEndTime = block.timestamp + biddingTime;
        }

        if(highestBid != 0) {
            pendingReturns[highestBidder] = highestBid;
        }

        highestBidder = user;
        highestBid = userContribution + value;
        pendingReturns[user] = 0;

        emit HighestBidIncrease(user, highestBid);

        Bid memory newBid = Bid(payable(user), highestBid, block.timestamp);
        bidders.push(newBid);
    }

    function withdrawal(address payable user) public payable returns(bool) {
        uint256 amount = pendingReturns[user];
        if(amount > 0) {
            pendingReturns[user] = 0;

            (bool success, ) = payable(user).call{value:amount, gas: 3000000}("");
            if(!success) {
                pendingReturns[user] = amount;
                emit ErrorWithdrawal(user, 'fail to send');
                return false;
            }
            emit Withdrawal(user, amount);
        } else {
            emit ErrorWithdrawal(user, 'amount <= 0');
            return false;
        }
        return true;
    }

    function Claim(address payable user) public payable returns (address)  {
        require(block.timestamp >= auctionEndTime, 'Auction has not ended yet!');
        require(ended == false, 'Auction has already been claimed!');
        require(user == highestBidder, 'Caller is not highest bidder!');

        (bool success, ) = payable(beneficiary).call{value:highestBid, gas: 3000000}("");
        if(!success) {
            return address(0);
        }
        ended = true;
        emit ClaimHighestBidder(highestBidder, highestBid);
        return highestBidder;
    }

    function timeRemaining() public view returns (uint256) {
        return (auctionEndTime > block.timestamp) ? (auctionEndTime - block.timestamp) : 0;
    }

    function auctionForwardFunds(address caller) external {
      require(caller == beneficiary, 'Caller is not owner');

      uint256 balance = address(this).balance;
      (bool success, ) = payable(beneficiary).call{value:balance, gas: 3000000}('');
    }


    /**
     * @dev receive function
     */
    receive() external payable {
    }

    /**
     * @dev fallback function
     */
    fallback() external payable {
      address user = address(abi.decode(msg.data, (address)));
      emit ReceivedAmount(user, msg.value);
      bid(payable(user), msg.value);
    }
}
