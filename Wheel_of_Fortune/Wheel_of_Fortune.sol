// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./Rune.sol";

contract FGCTicketSystem is
    VRFConsumerBaseV2,
    IERC721Receiver,
    Pausable,
    Ownable
{
    VRFCoordinatorV2Interface COORDINATOR;

    uint64 s_subscriptionId;
    address vrfCoordinator = 0xc587d9053cd1118f25F645F9E08BB98c9712A4EE;
    bytes32 keyHash =
        0x114f3da0a805b6a67d6e9cd2ec746f7028f1b7376365af575cfea3550dd1aa04;


    // Depends on the number of requested values that you want sent to the
    // fulfillRandomWords() function. Storing each word costs about 20,000 gas,
    // so 100,000 is a safe default for this example contract. Test and adjust
    // this limit based on the network that you select, the size of the request,
    // and the processing of the callback request in the fulfillRandomWords()
    // function.
    uint32 callbackGasLimit = 2500000;

    // The default is 3, but you can set this higher.
    uint16 requestConfirmations = 3;

    // Retrieve 100 random values in one request.
    // Cannot exceed VRFCoordinatorV2.MAX_NUM_WORDS.
    uint32 numWords = 100;

    uint256[] private s_randomWords;
    uint256 private s_requestId;

    address private RuneNFTAddress;
    uint256 private lastSupriseTokenIdTransfered;

    struct AwardERC721 {
        address addr;
        uint256 tokenId;
    }

    struct Range {
        uint256 minRange;
        uint256 maxRange;
        string Type;
    }

    Range[] public ranges;

    mapping(uint256 => AwardERC721[]) public NFTs;

    uint256 private RANGE_DIVIDER = 99999;

    using SafeMath for uint256;

    address payable private factoryBeneficiary;
    address private Aggregator;

    AggregatorV3Interface internal priceFeed;
    //false means ChainLink getLatestPrice. true means price set by owner
    bool private priceFlag = false;
    uint256 private ownerPrice = 0;
    uint256 public ticketPrice = 10;

    // Mapping approvedContracts address
    mapping(address => bool) private approvedContracts;
    mapping(address => uint256) public playerTickets;
    mapping(address => string) public playerLastAward;

    uint256 randomListSize = 100;
    uint256 private randomIndex = 0;
    uint256 private repeatTimes = 5;
    uint256 private incrementNumber;
    uint256 private state = 0;

    event NeedNewRandomRequest();
    event PlayerTicketBought(
        address player,
        uint256 ticketCount,
        uint256 ticketTotal
    );
    event PlayerRandomNumber(address player, uint256 randomNumber);
    event RequestNewRandomList(address player);

    event ERC721Won(
        address player,
        address contract_address,
        uint256 tokenId,
        string Type
    );
    event ERC721WonDelay(
        address player, 
        string Type
    );
    event TicketWon(address player, uint256 ticketCount, uint256 ticketTotal);
    event SendRune(address player, uint256 tokenId);

    constructor(uint64 subscriptionId, address payable _beneficiary, address _RuneNFTAddress)
        VRFConsumerBaseV2(vrfCoordinator)
    {
        COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
        s_subscriptionId = subscriptionId;

        factoryBeneficiary = _beneficiary;
        RuneNFTAddress = _RuneNFTAddress;

        /**
         * Network: Binance Smart Chain
         * Aggregator: BNB/USD
         * Address: 0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE
         */
        Aggregator = 0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE;
        priceFeed = AggregatorV3Interface(0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE);
    }

    function SetRuneNFTaddress(address _RuneNFTAddress) external ownerOrApprovedByOwner {
        RuneNFTAddress = _RuneNFTAddress;
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function setAggregatorV3Interface(address _Aggregator) external onlyOwner {
        Aggregator = _Aggregator;
        priceFeed = AggregatorV3Interface(Aggregator);
    }

    /**
     * @dev Pause crowdsale only by owner
     */
    function pause() external ownerOrApprovedByOwner {
        _pause();
    }

    /**
     * @dev Unpause crowdsale only by owner
     */
    function unpause() external ownerOrApprovedByOwner {
        _unpause();
    }

    /**
     * @dev _approvedRemoveContracts `to` to false
     *
     */
    function _approvedRemoveContracts(address to) external onlyOwner {
        approvedContracts[to] = false;
    }

    /**
     * @dev approvedContracts `to` to true
     *
     */
    function _approvedContracts(address to) external onlyOwner {
        approvedContracts[to] = true;
    }

    /**
     * @dev _getApprovedContracts
     *
     */
    function _getApprovedContracts(address to) public view returns (bool) {
        return approvedContracts[to];
    }

    modifier ownerOrApprovedByOwner() {
        require(
            msg.sender == owner() || _getApprovedContracts(msg.sender),
            "Not owner nor approved by owner"
        );
        _;
    }

    function setBeneficiaryAddress(address payable _factoryBeneficiary)
        external
        onlyOwner
    {
        factoryBeneficiary = _factoryBeneficiary;
    }

    function setTicketPrice(uint256 _ticketPrice)
        external
        ownerOrApprovedByOwner
    {
        ticketPrice = _ticketPrice;
    }

    function setOwnerPrice(uint256 _ownerPrice) external ownerOrApprovedByOwner {
        if (_ownerPrice == 0) {
            ownerPrice = uint256(getLatestPrice());
            priceFlag = false;
        } else {
            ownerPrice = _ownerPrice;
            priceFlag = true;
        }
    }

    function checkAmount(uint256 _value, uint256 _ticketCount)
        internal
        returns (bool)
    {
        if (!priceFlag) {
            ownerPrice = uint256(getLatestPrice());
        }

        require(ownerPrice > 1, "Wrong bnb price!");

        uint256 lowerPriceLimit = (_ticketCount *
            ticketPrice *
            1000000000000000000) / ownerPrice;

        if (_value >= lowerPriceLimit) {
            return true;
        } else {
            return false;
        }
    }

    //chianlink parnership airdrop
    function airdropTickets(
        address[] calldata _to,
        uint256[] calldata _ticketCount
    ) external ownerOrApprovedByOwner {
        require(
            _to.length == _ticketCount.length,
            "Receivers and IDs are different length"
        );
        for (uint256 i = 0; i < _to.length; i++) {
            playerTickets[_to[i]] =
                playerTickets[_to[i]] +
                _ticketCount[i];
        }
    }

    function removeUserArrayTickets(
        address[] calldata _to
    ) external ownerOrApprovedByOwner {
        for (uint256 i = 0; i < _to.length; i++) {
            playerTickets[_to[i]] = 0;
        }
    }

    /**
     * Returns the latest price
     */
    function getLatestPrice() public view returns (uint256) {
        require(Aggregator != address(0), "Price Aggregator not set!");
        (, int256 price, , , ) = priceFeed.latestRoundData();
        return uint256(price).div(100000000);
    }

    function forwardFunds() external ownerOrApprovedByOwner {
        uint256 balance = address(this).balance;
        (bool success, ) = payable(factoryBeneficiary).call{
            value: balance,
            gas: 3000000
        }("");
    }

    function requestRandomWordsFGC() public ownerOrApprovedByOwner {
        s_requestId = COORDINATOR.requestRandomWords(
            keyHash,
            s_subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );
    }

    function fulfillRandomWords(
        uint256, /* requestId */
        uint256[] memory randomWords
    ) internal override {
        s_randomWords = randomWords;
    }

    function buyTickets(uint256 ticketCount) external payable whenNotPaused {
        require(ticketCount > 0, "nft count is 0");
        require(checkAmount(msg.value, ticketCount), "Not enough BNB sent!");

        playerTickets[msg.sender] = playerTickets[msg.sender] + ticketCount;
        emit PlayerTicketBought(
            msg.sender,
            ticketCount,
            playerTickets[msg.sender]
        );

        uint256 balance = address(this).balance;
        (bool success, ) = payable(factoryBeneficiary).call{
            value: balance,
            gas: 3000000
        }("");
    }

    function getRandom() internal returns (uint256) {
        uint256 randomNumber = 0;

        if(state == 1) {
            randomNumber = s_randomWords[randomIndex];
            uint tempRandom = uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty, msg.sender))) % (randomListSize - 1);
            randomIndex = (randomNumber.add(tempRandom)) % randomListSize;
            incrementNumber ++;
            
            if(incrementNumber >= randomListSize * repeatTimes) {
                state = 0;
                randomIndex = 0;

                approvedContracts[msg.sender] = true;
                requestRandomWordsFGC();
                approvedContracts[msg.sender] = false;
                emit RequestNewRandomList(msg.sender);
            }
        } else {
            randomNumber = s_randomWords[randomIndex];
            randomIndex ++;
            
            if(randomIndex >= randomListSize - 1) {
                state = 1;
                incrementNumber = randomIndex;
            }
        }
        
        return randomNumber;
    }

    function setState(uint256 _state)
        external
        ownerOrApprovedByOwner
    {
        state = _state;
    }

    function setRepeatTimes(uint256 _repeatTimes)
        external
        ownerOrApprovedByOwner
    {
        repeatTimes = _repeatTimes;
    }

    function setIncrementNumber(uint256 _incrementNumber)
        external
        ownerOrApprovedByOwner
    {
        incrementNumber = _incrementNumber;
    }

    function setRandomIndex(uint256 _randomIndex)
        external
        ownerOrApprovedByOwner
    {
        randomIndex = _randomIndex;
    }

    function setRandomListSize(uint256 _randomListSize)
        external
        ownerOrApprovedByOwner
    {
        randomListSize = _randomListSize;
    }

    function transferRune() internal {
        for (uint256 tokenId = lastSupriseTokenIdTransfered; tokenId <= type(uint256).max; tokenId++) {
            if (Rune(RuneNFTAddress).ownerOf(tokenId) == address(this)) {
                Rune(RuneNFTAddress).safeTransferFrom(address(this),
                    msg.sender,
                    lastSupriseTokenIdTransfered
                );

                emit SendRune(msg.sender, lastSupriseTokenIdTransfered);
                lastSupriseTokenIdTransfered ++;
                break;
            }
        }
    }

    function startSpin() external whenNotPaused {
        require(playerTickets[msg.sender] > 0, "Not enough tickets!");

        playerTickets[msg.sender] = playerTickets[msg.sender] - 1;

        uint256 randomNumber = getRandom();
        emit PlayerRandomNumber(msg.sender, randomNumber);

        uint256 rangeIndex = returnRangeIndexFromRandom(randomNumber);
        string memory Type = ranges[rangeIndex].Type;
        playerLastAward[msg.sender] = Type;
        bytes32 _typeBytes = keccak256(bytes(Type));

        if (_typeBytes == keccak256(bytes("TICKET2"))) {
            playerTickets[msg.sender] = playerTickets[msg.sender] + 2;
            transferRune();
            emit TicketWon(msg.sender, 2, playerTickets[msg.sender]);
        } else if (_typeBytes == keccak256(bytes("TICKET1"))) {
            playerTickets[msg.sender] = playerTickets[msg.sender] + 1;
            transferRune();
            emit TicketWon(msg.sender, 1, playerTickets[msg.sender]);
        } else if (_typeBytes == keccak256(bytes("RUNE"))) {
            transferRune();
        } else {
            if (checkValidERC721(rangeIndex)) {
                takeWinNFTs(rangeIndex);
            } else {
                emit ERC721WonDelay(msg.sender, Type);
            }
        }
    }

    //NFT region
    function returnRangeIndexFromRandom(uint256 number)
        internal
        view
        returns (uint256)
    {
        uint256 newNumber = number % RANGE_DIVIDER;

        for(uint256 i = 0; i < ranges.length; i ++) {
            if(newNumber <= ranges[i].maxRange) {
                if(newNumber >= ranges[i].minRange) {
                    return i;
                }
            }
        }
        return 0;
    }

    function setRangeDivider(uint256 _maxRange) external ownerOrApprovedByOwner {
        RANGE_DIVIDER = _maxRange;
    }

    //upperLower (0/1) - 0 is minRange | 1 is maxRange
    function modifyRange(
        uint256 rangeIndex,
        uint256 upperLower,
        uint256 value,
        string memory Type
    ) external ownerOrApprovedByOwner {
        require(ranges.length > 0, "range elements count is 0");
        require(rangeIndex >= 0 && rangeIndex < ranges.length, "invalid Range");
        require(upperLower == 0 || upperLower == 1, "invalid upperLower");

        if (keccak256(bytes(Type)) != keccak256(bytes(""))) {
            ranges[rangeIndex].Type = Type;
        }

        if (upperLower == 0) {
            ranges[rangeIndex].minRange = value;
            if (rangeIndex > 0) {
                ranges[rangeIndex - 1].maxRange = value - 1;
            }
        } else {
            ranges[rangeIndex].maxRange = value;
            if (rangeIndex + 1 < ranges.length) {
                ranges[rangeIndex + 1].minRange = value + 1;
            }
        }
    }

    function addRangeStruct(
        Range calldata _range,
        AwardERC721[] calldata _NFTs
    ) public ownerOrApprovedByOwner {
        ranges.push(_range);
        uint256 index = ranges.length - 1;
        for (uint256 i = 0; i < _NFTs.length; i++) {
            NFTs[index].push(_NFTs[i]);
        }
    }

    function initStruct(Range[] calldata _range, AwardERC721[][] calldata _NFTs) external ownerOrApprovedByOwner {
        require(_range.length == _NFTs.length, 'invalid NFT array');

        for(uint256 i = 0; i < _range.length; i++) {
            addRangeStruct(_range[i], _NFTs[i]);
        }
    }

    function addAward721ListOnRangeIndex(
        uint256 rangeIndex,
        AwardERC721[] calldata _NFTs
    ) external ownerOrApprovedByOwner {
        for (uint256 i = 0; i < _NFTs.length; i++) {
            NFTs[rangeIndex].push(_NFTs[i]);
        }
    }

    function modifyAward721OnRangeIndex(
        uint256 RangeIndex,
        uint256 NFTIndex,
        address NFTaddress,
        uint256 tokenId
    ) external ownerOrApprovedByOwner {
        NFTs[RangeIndex][NFTIndex].addr = NFTaddress;
        NFTs[RangeIndex][NFTIndex].tokenId = tokenId;
    }

    function takeWinNFTs(uint256 index) internal {
        address contract_address = NFTs[index][NFTs[index].length - 1].addr;
        uint256 token_id = NFTs[index][NFTs[index].length - 1].tokenId;

        IERC721(contract_address).safeTransferFrom(
            address(this),
            msg.sender,
            token_id
        );
        emit ERC721Won(
            msg.sender,
            contract_address,
            token_id,
            ranges[index].Type
        );
        NFTs[index].pop();
    }

    function checkValidERC721(uint256 RangeIndex) internal view returns (bool) {
        if (
            NFTs[RangeIndex].length > 0 &&
            NFTs[RangeIndex][NFTs[RangeIndex].length - 1].addr != address(0)
        ) {
            return true;
        }
        return false;
    }

    function withdrawNFTS(address to, address[] calldata NFTaddr, uint256[] calldata tokenId) external ownerOrApprovedByOwner {
        require(NFTaddr.length == tokenId.length, 'invalid sizes');
        for(uint256 i = 0; i < NFTaddr.length; i ++) {
            IERC721(NFTaddr[i]).safeTransferFrom(address(this), to, tokenId[i]);
        }
    }

    function burnRune(address[] calldata from, address[] calldata to, uint256[] calldata tokenId) external ownerOrApprovedByOwner {
        require(from.length == tokenId.length, 'invalid sizes');
        for(uint256 i = 0; i < from.length; i ++) {
            Rune(RuneNFTAddress).safeTransferFrom(from[i], to[i], tokenId[i]);
        }
    }

    function removeRewardList(uint256 rewardIndex) public ownerOrApprovedByOwner {
        uint256 size = NFTs[rewardIndex].length;
        for(uint256 i = 0; i < size; i ++) {
            NFTs[rewardIndex].pop();
        }
    }

    function removeRange() public ownerOrApprovedByOwner {
        removeRewardList(ranges.length - 1);
        ranges.pop();
    }

    function removeAllRanges() external ownerOrApprovedByOwner {
        uint256 size = ranges.length;
        for(uint256 i = 0; i < size; i ++) {
            removeRange();
        }
    }
}