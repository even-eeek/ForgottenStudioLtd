// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import './TokenVestingPool.sol';
import "./OZ_legacy/TokenVesting.sol";


contract FtcTokenCrowdsale is Ownable, Pausable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for ERC20;

    AggregatorV3Interface internal priceFeed;
    //false means ChainLink getLatestPrice. true means price set by owner
    bool private priceFlag = false;
    uint256 public ownerPrice;

    // The token being sold
    ERC20 private token;

    // Address where funds are collected
    address payable private wallet;

    uint256 private investorMinCap = 200000000000000000; // 0.2 bnb
    uint256 private investorHardCap = 5000000000000000000; // 5 bnb

    mapping(address => uint256) private tokenPurchases;
    mapping(address => uint256) private tokenPayments;
    mapping(uint256 => address) private beneficiaries;

    uint256 private totalTokensPurchased;
    uint256 private totalBeneficiaries;

    mapping(address => uint256) private VCshare;
    mapping(uint256 => address) private VCs;

    uint256 private totalVCshare;
    uint256 private totalVCs;
    
    // Crowdsale Stages
    enum CrowdsaleStage {PreICO, ICO, PostICO}
    CrowdsaleStage private stage = CrowdsaleStage.PreICO;

    bool private tokenDistributionComplete = false;
    bool private NEXTYPEDistributionComplete = false;
    bool private VCDistributionComplete = false;

    TokenVesting private foundationEscrow1;
    TokenVesting private foundationEscrow2;
    TokenVesting private gameEscrow;
    TokenVesting private NextypeEscrow;
    TokenVestingPool private tokenSaleEscrow;
    TokenVestingPool private VCEscrow;

    address private liquidityAndMarketingFund;
    address private foundationFund;
    address private gameFund;
    address private NEXTYPE_FUND;

    uint256 constant private LIQUIDITY_AND_MARKETING_SHARE = 50000000000000000000000000;
    
    uint256 constant private GLOBAL_CLIFF = 14 days;

    uint256 private NEXTYPE_PERCENT = 100;
    uint256 constant private NEXTYPE_SHARE = 50000000000000000000000000;
    uint256 constant private NEXTYPE_ESCROW_DURATION = 840 days; //28 months | 15 months 450 days;

    uint256 constant private VC_MAX_SHARE = 50000000000000000000000000;
    uint256 constant private VC_ESCROW_DURATION = 840 days; //28 months | 15 months 450 days;

    uint256 constant private FOUNDATION_1_ESCROW_SHARE = 10000000000000000000000000;
    uint256 constant private FOUNDATION_1_ESCROW_DURATION = 300 days; //10 months

    uint256 constant private FOUNDATION_2_ESCROW_SHARE = 90000000000000000000000000;
    uint256 constant private FOUNDATION_2_ESCROW_DURATION = 540 days; //18 months

    uint256 constant private GAME_SHARE = 650000000000000000000000000;
    uint256 constant private GAME_ESCROW_DURATION = 2555 days; //7 years

    uint256 constant private CROWDSALE_ESCROW_DURATION = 450 days; //15 months

    /**
     * Event for token purchase logging
     * @param purchaser who paid for the tokens
     * @param beneficiary who got the tokens
     * @param value weis paid for purchase
     * @param amount amount of tokens purchased
     */
    event TokenPurchase(address indexed purchaser, address indexed beneficiary, uint256 value, uint256 amount);

    /**
     * Event for adding VC
     * @param beneficiary address of VC 
     * @param BNBamount beneficiary BNB amount
     * @param FTCamount beneficiary FTC amount
     */
    event OldBeneficiaryAdded(address indexed beneficiary, uint256 BNBamount, uint256 FTCamount);
    
    /**
     * Event for adding VC
     * @param VC address of VC 
     * @param amount VC FTC amount
     */
    event VCadded(address indexed VC, uint256 amount);
    
    event Received(address, uint256);

    constructor(
        address payable _wallet,
        ERC20 _token,
        address _nextype
    )
    {
        foundationFund = _wallet;
        liquidityAndMarketingFund = _wallet;
        gameFund = _wallet;
        token = _token;
        wallet = _wallet;
        NEXTYPE_FUND = _nextype;
 
        /**
        * Network: Binance Smart Chain
        * Aggregator: BNB/USD
        * Address: 0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE
        */
        priceFeed = AggregatorV3Interface(0x2514895c72f50D8bd4B4F9b1110F0D6bD2c97526); //testnet
        // priceFeed = AggregatorV3Interface(0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE); //mainnet 
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

    /**
     * @dev Set BNB/USD price manually in case ChainLink fails. If the new price is 0, then resume with ChainLink Aggregator Interface
     * @param _ownerPrice new price for 1 BNB
     */
    function setOwnerPrice(uint256 _ownerPrice) public onlyOwner {
      if(_ownerPrice == 0 ) {
        ownerPrice = uint256(getLatestPrice());
        priceFlag = false;
      } else {
        ownerPrice = _ownerPrice;
        priceFlag = true;
      }
    }

    /**
     * @param _weiAmount Value in wei to be converted into tokens
     * @return Number of tokens that can be purchased with the specified _weiAmount
     */
    function _getTokenAmount(uint256 _weiAmount) internal returns (uint256) {
        if(!priceFlag) {
          ownerPrice = uint256(getLatestPrice());
        }

        uint256 newRate = 0;
        if (CrowdsaleStage.PreICO == stage) {
          newRate = ownerPrice.mul(20);
        } else if (CrowdsaleStage.ICO == stage) {
          newRate = ownerPrice.mul(20).div(3);
        }

        return _weiAmount.mul(newRate);
    }

    /**
     * @dev receive function
     */
    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    /**
     * @dev fallback function
     */
    fallback() external payable {
        buyTokens(msg.sender);
    }

    /**
     * @dev Add VC to VC list that will be used for the VC Escrow Vesting Pool contract
     * @param _beneficiary Address of the VC
     * @param VC_amount FTC amount for the given VC
     */
    function addVC(address _beneficiary, uint256 VC_amount) public onlyOwner {
        require(totalVCshare.add(VC_amount) <= VC_MAX_SHARE, 'VC share max cap');

        totalVCshare = totalVCshare.add(VC_amount);
        VCshare[_beneficiary] = VC_amount;
        VCs[totalVCs] = _beneficiary;
        totalVCs = totalVCs.add(1);

        emit VCadded(_beneficiary, VC_amount);
    }

    /**
     * @dev Init VC Escrow Vesting Pool contract
     */
    function initVCVesting() public onlyOwner() {
        require(VCDistributionComplete == false, 'VC vesting started');

        VCEscrow = new TokenVestingPool(token, totalVCshare);
        token.safeTransfer(address(VCEscrow), totalVCshare);
        for (uint256 i = 0; i < totalVCs; i++) {
            address beneficiary = VCs[i];
            uint256 VC_vesting_share = VCshare[beneficiary];

            VCEscrow.addBeneficiary(
                beneficiary,
                block.timestamp,
                GLOBAL_CLIFF,
                VC_ESCROW_DURATION,
                VC_vesting_share
            );
        }
        VCDistributionComplete = true;
    }

    /**
     * @dev Set NEXTYPE address
     * @param _nextypeAddress New address of the NEXTYPE
     */
    function setNextypeAddress(address _nextypeAddress) public onlyOwner () {
        NEXTYPE_FUND = _nextypeAddress;
    }

    /**
     * @dev Set NEXTYPE percentage (0 - 100)
     * @param _nextypePercent New percentage for the NEXTYPE
     */
    function setNextypePerfect(uint256 _nextypePercent) public onlyOwner () {
        require(_nextypePercent >= 0 && _nextypePercent <= 100, 'wrong nextype address');
        
        NEXTYPE_PERCENT = _nextypePercent;
    }

    /**
     * @dev Init NEXTYPE Escrow Vesting contract
     */
    function initNextypeVesting() public onlyOwner () {
        require(NEXTYPEDistributionComplete == false, 'VC vesting started');

        NextypeEscrow = new TokenVesting(
            NEXTYPE_FUND,
            block.timestamp,
            GLOBAL_CLIFF,
            NEXTYPE_ESCROW_DURATION,
            false // TokenVesting cannot be revoked
        );

        token.safeTransfer(address(NextypeEscrow), NEXTYPE_SHARE.div(100).mul(NEXTYPE_PERCENT));
        NEXTYPEDistributionComplete = true;
    }

    /**
     * @dev Set old beneficiares info
     * @param _beneficiary Address array of the beneficiaries
     * @param _newPayment payment array of the beneficiaries
     * @param _tokens token array of the beneficiaries
     */
    function setBeneficiaryInfo(address _beneficiary, uint256 _newPayment, uint256 _tokens) public onlyOwner {

        require(_beneficiary != address(0), 'Invalid beneficiary');
        require(_newPayment != 0, 'Invalid payment');
        require(_tokens != 0, 'Invalid token count');
        
        totalTokensPurchased = totalTokensPurchased.add(_tokens);

        uint256 _existingPurchase = tokenPurchases[_beneficiary];
        uint256 _newPurchase = _existingPurchase.add(_tokens);

        tokenPayments[_beneficiary] = _newPayment;
        tokenPurchases[_beneficiary] = _newPurchase;

        if(_existingPurchase == 0) {
            beneficiaries[totalBeneficiaries] = _beneficiary;
            totalBeneficiaries = totalBeneficiaries.add(1);
        }

        emit OldBeneficiaryAdded(_beneficiary, _newPayment, _tokens);
    }

    /**
     * @dev Buy token functionality
     * @param _beneficiary Address performing the token purchase
     */
    function buyTokens(address _beneficiary) public payable whenNotPaused nonReentrant {
        require(CrowdsaleStage.PostICO != stage, "PostICO stage is active");

        if (CrowdsaleStage.PreICO == stage) {
            require(totalTokensPurchased < token.totalSupply().div(100).mul(3), "preICO all token sold");
        } else if (CrowdsaleStage.ICO == stage) {
            require(totalTokensPurchased < token.totalSupply().div(10), "ICO all token sold");
        }

        uint256 _weiAmount = msg.value;
        uint256 _existingPayment = tokenPayments[_beneficiary];
        uint256 _newPayment = _existingPayment.add(_weiAmount);

        require(_beneficiary != address(0));
        require(_weiAmount != 0);
        require(_newPayment >= investorMinCap && _newPayment <= investorHardCap);

        uint256 _tokens = _getTokenAmount(_weiAmount);
        totalTokensPurchased = totalTokensPurchased.add(_tokens);

        uint256 _existingPurchase = tokenPurchases[_beneficiary];
        uint256 _newPurchase = _existingPurchase.add(_tokens);

        emit TokenPurchase(msg.sender, _beneficiary, _weiAmount, _tokens);

        tokenPayments[_beneficiary] = _newPayment;
        tokenPurchases[_beneficiary] = _newPurchase;

        if(_existingPurchase == 0) {
          beneficiaries[totalBeneficiaries] = _beneficiary;
          totalBeneficiaries = totalBeneficiaries.add(1);
        }

        if (CrowdsaleStage.PreICO == stage && totalTokensPurchased >= token.totalSupply().div(100).mul(3)) {
            _pause();
        } else if (CrowdsaleStage.ICO == stage && totalTokensPurchased >= token.totalSupply().div(10)) {
            _pause();
        }
        
        uint256 balance = address(this).balance;
        if(balance > 0) {
            (bool success, ) = payable(wallet).call{value:balance}('');

            // require(success, 'Failed to forwad funds');
        }
    }

    /**
     * @dev Pause crowdsale only by owner
     */
    function pause() public onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause crowdsale only by owner
     */
    function unpause() public onlyOwner {
        _unpause();
    }

    // /**
    //  * @dev Returns the amount contributed so far by a sepecific user.
    //  * @param _beneficiary Address of contributor
    //  * @return User contribution so far
    //  */
    // function getUserContribution(address _beneficiary) public view returns (uint256) {
    //     return tokenPayments[_beneficiary];
    // }

    /**
     * @dev Allows admin to update the crowdsale stage
     * @param _stage Crowdsale stage
     */
    function incrementCrowdsaleStage(uint256 _stage) public onlyOwner nonReentrant {
        require(CrowdsaleStage.PostICO != stage, "PostICO is active");
        require(uint256(stage) == uint256(_stage.sub(1)), "Stage incorectly");

        if (uint(CrowdsaleStage.PreICO) == _stage) {
            stage = CrowdsaleStage.PreICO;
            
        } else if (uint(CrowdsaleStage.ICO) == _stage) {
            investorHardCap = 15000000000000000000; //15 bnb
            stage = CrowdsaleStage.ICO;
            
        } else if (uint(CrowdsaleStage.PostICO) == _stage) {
            stage = CrowdsaleStage.PostICO;
        }
    }

    /**
     * @dev Allows admin to update the crowdsale hardcap to 20BNB
     */
    function updateCrowdsaleHardCap20BNB() public onlyOwner nonReentrant {
        investorHardCap = 20000000000000000000; // 20 bnb
    }

    /**
     * @dev Allows admin to update the crowdsale hardcap to 30BNB
     */
    function updateCrowdsaleHardCap30BNB() public onlyOwner nonReentrant {
        investorHardCap = 30000000000000000000; // 30 bnb
    }

    /**
     * @dev enables token transfers and escrow creation when ICO is over
     */
    function distributeTokens() public onlyOwner nonReentrant {
        require(CrowdsaleStage.PostICO == stage, "PostICO not active");
        require(token.totalSupply() == uint256(1000000000).mul(10 ** 18), "Total supply not 1B");
        require(tokenDistributionComplete == false, "Distribution completed.");

        token.safeTransfer(liquidityAndMarketingFund, LIQUIDITY_AND_MARKETING_SHARE);

        foundationEscrow1 = new TokenVesting(
            foundationFund,
            block.timestamp,
            GLOBAL_CLIFF,
            FOUNDATION_1_ESCROW_DURATION,
            false // TokenVesting cannot be revoked
        );
        token.safeTransfer(address(foundationEscrow1), FOUNDATION_1_ESCROW_SHARE);

        foundationEscrow2 = new TokenVesting(
            foundationFund,
            block.timestamp + FOUNDATION_1_ESCROW_DURATION + 1 days,
            GLOBAL_CLIFF,
            FOUNDATION_2_ESCROW_DURATION,
            false // TokenVesting cannot be revoked
        );
        token.safeTransfer(address(foundationEscrow2), FOUNDATION_2_ESCROW_SHARE);

        //90% of all tokensPurchased because 10% for each individual will be transfered at TGE 
        uint256 tokensPurchasedRemaining = totalTokensPurchased.div(10).mul(9); 

        tokenSaleEscrow = new TokenVestingPool(token, tokensPurchasedRemaining);
        token.safeTransfer(address(tokenSaleEscrow), tokensPurchasedRemaining);
        for (uint256 i = 0; i < totalBeneficiaries; i++) {
            address beneficiary = beneficiaries[i];
            uint256 purchase = tokenPurchases[beneficiary];
            
            uint256 TGEpurchase = purchase.div(10);
            token.safeTransfer(beneficiary, TGEpurchase);

            tokenSaleEscrow.addBeneficiary(
                beneficiary,
                block.timestamp,
                GLOBAL_CLIFF,
                CROWDSALE_ESCROW_DURATION,
                purchase.sub(TGEpurchase) 
            );
        }

        gameEscrow = new TokenVesting(
            gameFund,
            block.timestamp,
            GLOBAL_CLIFF,
            GAME_ESCROW_DURATION,
            false // TokenVesting cannot be revoked
        );
        token.safeTransfer(address(gameEscrow), GAME_SHARE);

        _forwardFunds();
        tokenDistributionComplete = true;
    }

    /**
     * @dev Get VC Vesting Contract
     * @param VC Address of the VC
     * @return VC Vesting Contract
     */
    function getVCVestedContract(address VC) internal view returns (address){
        require(VCDistributionComplete == true, "VC not started");

        address[] memory addressVCSaleEscrow = VCEscrow.getDistributionContracts(VC);
        return addressVCSaleEscrow[0];
    }

    /**
     * @dev Get beneficiary Token Sale Vesting Contract
     * @param beneficiary Address of the beneficiary
     * @return beneficiary Vesting Contract
     */
    function getTokenSaleVestedContract(address beneficiary) internal view returns (address){
        require(tokenDistributionComplete == true, "ICO not finished");

        address[] memory addressTokenSaleEscrow = tokenSaleEscrow.getDistributionContracts(beneficiary);
        return addressTokenSaleEscrow[0];
    }

    /**
     * @dev Get Foundation1 Vested Funds
     * @return Foundation1 Vested Funds so far
     */
    function getFoundationVestedFunds1() public view returns (uint256) {
        require(tokenDistributionComplete == true, "ICO not finished");

        address addressFoundationEscrow1 = address(foundationEscrow1);
        return token.balanceOf(addressFoundationEscrow1);
    }

    /**
     * @dev Get Foundation2 Vested Funds
     * @return Foundation2 Vested Funds so far
     */
    function getFoundationVestedFunds2() public view returns (uint256) {
        require(tokenDistributionComplete == true, "ICO not finished");

        address addressFoundationEscrow2 = address(foundationEscrow2);
        return token.balanceOf(addressFoundationEscrow2);
    }

    /**
     * @dev Get NEXTYPE Vested Funds
     * @return NEXTYPE Vested Funds so far
     */
    function getNEXTYPEVestedFunds() public view returns (uint256) {
        require(NEXTYPEDistributionComplete == true, "Nextype not started");

        address addressNextypeEscrow = address(NextypeEscrow);
        return token.balanceOf(addressNextypeEscrow);
    }

    /**
     * @dev Get VC Vested Funds Amount
     * @param VC Address of the VC
     * @return VC Vested Funds so far
     */
    function getVCVestedFunds(address VC) public view returns (uint256){
        address addressVCEscrow = getVCVestedContract(VC);
        return token.balanceOf(addressVCEscrow);
    }

    /**
     * @dev Get Beneficiary Token Sale Funds Amount
     * @param beneficiary Address of the beneficiary
     * @return Beneficiary Vested Funds so far
     */
    function getTokenSaleVestedFunds(address beneficiary) public view returns (uint256){
        address addressTokenSaleEscrow = getTokenSaleVestedContract(beneficiary);
        return token.balanceOf(addressTokenSaleEscrow);
    }

    /**
     * @dev Get Game Vested Funds Amount
     * @return Game Vested Funds so far
     */
    function getGameVestedFunds() public view returns (uint256) {
        require(tokenDistributionComplete == true, "ICO not finished");

        address addressGameEscrow = address(gameEscrow);
        return token.balanceOf(addressGameEscrow);
    }

    /**
     * @dev Release Foundation1 Vested Funds
     */
    function releaseFoundationVestedFunds1() public {
        require(tokenDistributionComplete == true, "ICO not finished");

        address addressFoundationEscrow1 = address(foundationEscrow1);
        TokenVesting(addressFoundationEscrow1).release(token);
    }

    /**
     * @dev Release Foundation2 Vested Funds
     */
    function releaseFoundationVestedFunds2() public {
        require(tokenDistributionComplete == true, "ICO not finished");

        address addressFoundationEscrow2 = address(foundationEscrow2);
        TokenVesting(addressFoundationEscrow2).release(token);
    }

    /**
     * @dev Release NEXTYPE Vested Funds
     */
    function releaseNEXTYPEVestedFunds() public {
        require(NEXTYPEDistributionComplete == true, "Nextype not started");

        address addressNEXTYPEEscrow = address(NextypeEscrow);
        TokenVesting(addressNEXTYPEEscrow).release(token);
    }

    /**
     * @dev Release VC Vested Funds
     * @param VC Address of the VC
     */
    function releaseVCVestedFunds(address VC) public {
        address addressVCEscrow = getVCVestedContract(VC);
        TokenVesting(addressVCEscrow).release(token);
    }

    /**
     * @dev Release Beneficiary Token Sale Funds
     * @param beneficiary Address of the user
     */
    function releaseTokenSaleVestedFunds(address beneficiary) public {
        address addressTokenSaleEscrow = getTokenSaleVestedContract(beneficiary);
        TokenVesting(addressTokenSaleEscrow).release(token);
    }

    /**
     * @dev Release Game Vested Funds
     */
    function releaseGameVestedFunds() public {
        require(tokenDistributionComplete == true, "ICO not finished");

        address addressGameEscrow = address(gameEscrow);
        TokenVesting(addressGameEscrow).release(token);
    }

    /**
     * @dev Forwards the BNB funds of the crowdsale
     */
    function _forwardFunds() public onlyOwner {
        uint256 balance = address(this).balance;
        if(balance > 0) {
            (bool success, ) = payable(wallet).call{value:balance}('');

            // require(success, 'Failed to forwad funds');
        }
    }

    /**
     * @dev Forwards the FTC funds of the crowdsale
     */
    function _forwardFTC() public onlyOwner {
        uint256 balance = token.balanceOf(address(this));

        if(balance > 0) {
            token.safeTransfer(address(wallet), balance);

        }
    }
}