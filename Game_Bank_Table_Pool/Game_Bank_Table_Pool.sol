// SPDX-License-Identifier: MIT
// pragma solidity ^0.8.18;
pragma solidity >=0.8.0 <= 0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract ForgottenChroniclesTablePool is
    Pausable,
    Ownable,
    ReentrancyGuard
{
    using SafeMath for uint256;
    IERC20 FTCtoken;

    address payable private factoryBeneficiary;
    address payable private gameFund;
    mapping(address => bool) private approvedContracts;
    mapping(address => bool) private approvedAdmins;
    
    uint256 public penalty = 10; //for users that don't accept / reject the game

    struct TableNFTDetail {
        address addr;
        uint256 winPerc;
        uint256 tableOwnerPerc;
        uint256 gamePerc;
    }

    //paid:
    // 0 not paid
    // 1 paid
    // 2 initiated increase stake and not accepted -> for refund
    struct PlayingUser {
        address player;
        uint256 paid;
        uint256 FTC_refund;
        uint256 BNB_refund;
    }

    struct Table {
        uint256 tableId;
        uint256 rarity;
    }

    // Struct representing a game match
    struct GameMatch {
        string gameId;
        PlayingUser player1;
        PlayingUser player2;
        uint256 FTC_stake;
        uint256 BNB_stake;
        uint256 startTime;
        Table table;
        address winner;
    }
    
    struct UserBalance {
        uint256 FTC;
        uint256 BNB;
    }

    mapping(address => UserBalance) public userBalance;

    mapping(uint256 => TableNFTDetail) public tablesContractsByRarity;
    mapping(string => GameMatch) public Matches;

    event MatchRefunded(string gameId, uint256 tableID, address tableContract, uint256 refundTime);

    event SendStakeReward(string gameId, uint256 rarity, uint256 tableID, address tableContract, address tableOwner, address winner, address not_winner, 
                            address companyAddress, uint256 FTC_stake, uint256 BNB_stake, uint256 time);

    constructor(address payable _beneficiary, 
                address payable _gameFund, 
                IERC20 _FTCtoken)
    {
        factoryBeneficiary = _beneficiary;
        gameFund = _gameFund;
        FTCtoken = _FTCtoken;
    }

    function CheckRefundTables(string[] calldata GameIDs) external nonReentrant ownerOrApproved {
        for(uint256 i = 0; i < GameIDs.length; i ++) {
            //1 hour + 5 minutes for players payment and connection
            if(Matches[GameIDs[i]].startTime + 65 minutes <= block.timestamp && Matches[GameIDs[i]].winner == address(0)) {

                if(Matches[GameIDs[i]].FTC_stake > 0) {
                    uint256 totalPenalty = Matches[GameIDs[i]].FTC_stake.div(100).mul(penalty);
                    if(Matches[GameIDs[i]].player1.paid > 0) {
                        transferFTCtoUser(Matches[GameIDs[i]].player1.player, Matches[GameIDs[i]].FTC_stake.div(2).add(
                            Matches[GameIDs[i]].player1.FTC_refund));
                        if(Matches[GameIDs[i]].player1.BNB_refund > 0) {
                            transferBNBtoUser(Matches[GameIDs[i]].player1.player, Matches[GameIDs[i]].player1.BNB_refund);
                        }
                    } else {
                        removeUserFTC(Matches[GameIDs[i]].player1.player, totalPenalty);
                    }
                    if(Matches[GameIDs[i]].player2.paid > 0) {
                        transferFTCtoUser(Matches[GameIDs[i]].player2.player, Matches[GameIDs[i]].FTC_stake.div(2).add( 
                                                            Matches[GameIDs[i]].player2.FTC_refund));
                        if(Matches[GameIDs[i]].player2.BNB_refund > 0) {
                            transferBNBtoUser(Matches[GameIDs[i]].player2.player, Matches[GameIDs[i]].player2.BNB_refund);
                        }
                    } else {
                        removeUserFTC(Matches[GameIDs[i]].player2.player, totalPenalty);
                    }
                }

                if(Matches[GameIDs[i]].BNB_stake > 0) {
                    uint256 totalPenalty = Matches[GameIDs[i]].BNB_stake.div(100).mul(penalty);
                    if(Matches[GameIDs[i]].player1.paid > 0) {
                        transferBNBtoUser(Matches[GameIDs[i]].player1.player, Matches[GameIDs[i]].BNB_stake.div(2).add(
                                                            Matches[GameIDs[i]].player1.BNB_refund));
                        if(Matches[GameIDs[i]].player1.FTC_refund > 0) {
                            transferFTCtoUser(Matches[GameIDs[i]].player1.player, Matches[GameIDs[i]].player1.FTC_refund);
                        }
                    } else {
                        removeUserBNB(Matches[GameIDs[i]].player1.player, totalPenalty);
                    }
                    if(Matches[GameIDs[i]].player2.paid > 0) {
                        transferBNBtoUser(Matches[GameIDs[i]].player2.player, Matches[GameIDs[i]].BNB_stake.div(2).add(
                                                            Matches[GameIDs[i]].player2.BNB_refund)); 
                        if(Matches[GameIDs[i]].player2.FTC_refund > 0) {
                            transferFTCtoUser(Matches[GameIDs[i]].player2.player, Matches[GameIDs[i]].player2.FTC_refund);
                        }
                    } else {
                        removeUserBNB(Matches[GameIDs[i]].player2.player, totalPenalty);
                    }
                }

                emit MatchRefunded(GameIDs[i], Matches[GameIDs[i]].table.tableId, tablesContractsByRarity[Matches[GameIDs[i]].table.rarity].addr, block.timestamp);

                delete Matches[GameIDs[i]];
            }
        }
    }

    function RefundTable(string calldata GameID, address userFault) external nonReentrant ownerOrApproved {
        require(userFault == address(0) || Matches[GameID].player1.player == userFault || Matches[GameID].player2.player == userFault, "bad fault");
        if(Matches[GameID].FTC_stake > 0) {
            if(Matches[GameID].player1.paid > 0) {
                transferFTCtoUser(Matches[GameID].player1.player, Matches[GameID].FTC_stake.div(2));
            }
            if(Matches[GameID].player2.paid > 0) {
                transferFTCtoUser(Matches[GameID].player2.player, Matches[GameID].FTC_stake.div(2));
            }
            if(userFault != address(0)) {
                uint256 totalPenalty = Matches[GameID].FTC_stake.div(100).mul(penalty);
                removeUserFTC(userFault, totalPenalty);
            }
        } else if(Matches[GameID].BNB_stake > 0) {
            if(Matches[GameID].player1.paid > 0) {
                transferBNBtoUser(Matches[GameID].player1.player, Matches[GameID].BNB_stake.div(2));
            }
            if(Matches[GameID].player2.paid > 0) {
                transferBNBtoUser(Matches[GameID].player2.player, Matches[GameID].BNB_stake.div(2));
            }
            if(userFault != address(0)) {
                uint256 totalPenalty = Matches[GameID].BNB_stake.div(100).mul(penalty);
                removeUserBNB(userFault, totalPenalty);
            }
        }

        emit MatchRefunded(GameID, Matches[GameID].table.tableId, tablesContractsByRarity[Matches[GameID].table.rarity].addr, block.timestamp);

        delete Matches[GameID];
    }

    //FTC_OR_BNB (true means FTC, false BNB)
    function CreateMatch(string memory _gameID, uint256 _rarity, uint256 _tableId, address _player1, address _player2, uint256 _stakeFTC, uint256 _stakeBNB) external ownerOrApproved nonReentrant {
        require(Matches[_gameID].player1.player == address(0), "Match created");
        require(_player1 != address(0) && _player2 != address(0), "addr0");
        require(_rarity <= 4, "no table available!");

        bool b_FTC_game = _stakeFTC > 0;
        if(b_FTC_game) {
            require(userBalance[_player1].FTC >= _stakeFTC.div(2), "Fail send FTC 1");
            require(userBalance[_player2].FTC >= _stakeFTC.div(2), "Fail send FTC 2");
            userBalance[_player1].FTC = userBalance[_player1].FTC.sub(_stakeFTC.div(2));
            userBalance[_player2].FTC = userBalance[_player2].FTC.sub(_stakeFTC.div(2));
        } else {
            require(userBalance[_player1].BNB >= _stakeBNB.div(2), "Fail send BNB 1");
            require(userBalance[_player2].BNB >= _stakeBNB.div(2), "Fail send BNB 2");
            userBalance[_player1].BNB = userBalance[_player1].BNB.sub(_stakeBNB.div(2));
            userBalance[_player2].BNB = userBalance[_player2].BNB.sub(_stakeBNB.div(2));
        }

        Matches[_gameID] = GameMatch({
            gameId: _gameID,
            player1: PlayingUser(_player1, 1, 0, 0),
            player2: PlayingUser(_player2, 1, 0, 0),
            FTC_stake: _stakeFTC,
            BNB_stake: _stakeBNB,
            table: Table(_tableId, _rarity),
            winner: address(0),
            startTime: block.timestamp
        });
    }

    // function JoinMatch(string memory _gameID) external payable nonReentrant {
    //     require(Matches[_gameID].FTC_stake != 0 || Matches[_gameID].BNB_stake != 0, "not inited ");
    //     require(msg.sender == Matches[_gameID].player1.player || msg.sender == Matches[_gameID].player2.player, "Not expected");

    //     bool b_FTC_game = Matches[_gameID].FTC_stake > 0;
    //     if(b_FTC_game) {
    //         require(userBalance[msg.sender].FTC >= Matches[_gameID].FTC_stake.div(2), "Fail send FTC");
    //         userBalance[msg.sender].FTC = userBalance[msg.sender].FTC.sub(Matches[_gameID].FTC_stake.div(2));
    //     } else {
    //         require(userBalance[msg.sender].BNB >= Matches[_gameID].BNB_stake.div(2), "Fail send BNB");
    //         userBalance[msg.sender].BNB = userBalance[msg.sender].BNB.sub(Matches[_gameID].BNB_stake.div(2));
    //     }

    //     if (msg.sender == Matches[_gameID].player1.player) {
    //         require(Matches[_gameID].player1.paid == 0, "User1 paid");
    //         Matches[_gameID].player1.paid = 1;
    //     } else if (msg.sender == Matches[_gameID].player2.player) {
    //         require(Matches[_gameID].player2.paid == 0, "User2 paid");
    //         Matches[_gameID].player2.paid = 1;
    //     }
    // }

    function InitIncrementStake(string calldata gameID, uint256 stake, bool b_FTC_game) external payable nonReentrant {
        require(msg.sender == Matches[gameID].player1.player || msg.sender == Matches[gameID].player2.player, "Not expected");
        require(Matches[gameID].player1.paid == 1 && Matches[gameID].player2.paid == 1, "Not ready");

        if(b_FTC_game) {
            require(userBalance[msg.sender].FTC >= stake, "Fail send FTC");
            userBalance[msg.sender].FTC = userBalance[msg.sender].FTC.sub(stake);
        } else {
            require(userBalance[msg.sender].BNB >= stake, "Fail send BNB");
            userBalance[msg.sender].BNB = userBalance[msg.sender].BNB.sub(stake);
        }
        
        if (msg.sender == Matches[gameID].player1.player) {
            require(Matches[gameID].player1.paid == 1, "User1 init");
            Matches[gameID].player1.paid = 2;
            if(b_FTC_game) {
                Matches[gameID].player1.FTC_refund = stake;
            } else {
                Matches[gameID].player1.BNB_refund = stake;
            }
        } else if (msg.sender == Matches[gameID].player2.player) {
            require(Matches[gameID].player2.paid == 1, "User2 init");
            Matches[gameID].player2.paid = 2;
            if(b_FTC_game) {
                Matches[gameID].player2.FTC_refund = stake;
            } else {
                Matches[gameID].player2.BNB_refund = stake;
            }
        }
    }

    function AcceptIncrementStake(string calldata gameID) external payable nonReentrant {
        require(msg.sender == Matches[gameID].player1.player || msg.sender == Matches[gameID].player2.player, "Not expected");

        bool b_FTC_game = true;
        if(Matches[gameID].player1.BNB_refund > 0 || Matches[gameID].player2.BNB_refund > 0){
            b_FTC_game = false;
        }

        uint256 stake = 0;
        if(Matches[gameID].player1.paid == 2) {
            stake = b_FTC_game ? Matches[gameID].player1.FTC_refund : Matches[gameID].player1.BNB_refund;
        } else if (Matches[gameID].player2.paid == 2) {
            stake = b_FTC_game ? Matches[gameID].player2.FTC_refund : Matches[gameID].player2.BNB_refund;
        }

        if(b_FTC_game) {
            require(userBalance[msg.sender].FTC >= stake, "Fail send FTC");
            userBalance[msg.sender].FTC = userBalance[msg.sender].FTC.sub(stake);
        } else {
            require(userBalance[msg.sender].BNB >= stake, "Fail send BNB");
            userBalance[msg.sender].BNB = userBalance[msg.sender].BNB.sub(stake);
        }

        if (msg.sender == Matches[gameID].player1.player) {
            require(Matches[gameID].player1.paid == 1 && Matches[gameID].player2.paid == 2, "User1 init");
            Matches[gameID].player2.paid = 1;
            if(b_FTC_game) {
                Matches[gameID].player2.FTC_refund = 0;
            } else {
                Matches[gameID].player2.BNB_refund = 0;
            }
        } else if (msg.sender == Matches[gameID].player2.player) {
            require(Matches[gameID].player2.paid == 1 && Matches[gameID].player1.paid == 2, "User2 init");
            Matches[gameID].player1.paid = 1;
            if(b_FTC_game) {
                Matches[gameID].player1.FTC_refund = 0;
            } else {
                Matches[gameID].player1.BNB_refund = 0;
            }
        }
        //means both agreed so increment match stake
        if(b_FTC_game) {
            Matches[gameID].FTC_stake = Matches[gameID].FTC_stake.add(stake);
        } else if(b_FTC_game) {
            Matches[gameID].BNB_stake = Matches[gameID].BNB_stake.add(stake);
        }
    }

    function EndMatch(string memory _gameId, address _winner) external nonReentrant ownerOrApproved {
        require(Matches[_gameId].player1.paid > 0 && Matches[_gameId].player2.paid > 0, "Not paid");
        require(Matches[_gameId].player1.player == _winner || Matches[_gameId].player2.player == _winner, "Not expected");

        uint256 FTC_stake = Matches[_gameId].FTC_stake;
        uint256 BNB_stake = Matches[_gameId].BNB_stake;
        uint256 tableId = Matches[_gameId].table.tableId;
        uint256 rarity = Matches[_gameId].table.rarity;

        address owner = IERC721(tablesContractsByRarity[rarity].addr).ownerOf(tableId);
        address not_winner = Matches[_gameId].player1.player;
        if(not_winner == _winner)
            not_winner = Matches[_gameId].player2.player;

        CheckSendRefundFTC(Matches[_gameId].player1.FTC_refund, Matches[_gameId].player1.player);
        CheckSendRefundFTC(Matches[_gameId].player2.FTC_refund, Matches[_gameId].player2.player);
        CheckSendRefundBNB(Matches[_gameId].player1.BNB_refund, Matches[_gameId].player1.player);
        CheckSendRefundBNB(Matches[_gameId].player2.BNB_refund, Matches[_gameId].player2.player);

        if(Matches[_gameId].FTC_stake > 0) {
            uint256 winnerShare = (tablesContractsByRarity[rarity].winPerc * FTC_stake).div(100);
            uint256 tableOwnerShare = (tablesContractsByRarity[rarity].tableOwnerPerc * FTC_stake).div(100);
            uint256 companyShare = (tablesContractsByRarity[rarity].gamePerc * FTC_stake).div(100);

            transferFTCtoUser(_winner, winnerShare);
            transferFTCtoUser(owner, tableOwnerShare);
            transferFTCtoUser(gameFund, companyShare);
        }
        if(Matches[_gameId].BNB_stake > 0) {
            uint256 winnerShare = (tablesContractsByRarity[rarity].winPerc * BNB_stake).div(100);
            uint256 tableOwnerShare = (tablesContractsByRarity[rarity].tableOwnerPerc * BNB_stake).div(100);
            uint256 companyShare = (tablesContractsByRarity[rarity].gamePerc * BNB_stake).div(100);

            transferBNBtoUser(_winner, winnerShare);
            transferBNBtoUser(owner, tableOwnerShare);
            transferBNBtoUser(gameFund, companyShare);
        }
        emit SendStakeReward(_gameId, rarity, tableId, tablesContractsByRarity[rarity].addr, owner, _winner, not_winner, gameFund, FTC_stake, BNB_stake, block.timestamp);

        delete Matches[_gameId];
    }

    function CheckSendRefundFTC(uint256 refund, address player) internal {
        if(refund > 0) { transferFTCtoUser(player, refund); }
    }

    function CheckSendRefundBNB(uint256 refund, address player) internal {
        if(refund > 0) { transferBNBtoUser(player, refund); }
    }

    function pause() external ownerOrApproved {
        _pause();
    }

    function unpause() external ownerOrApproved {
        _unpause();
    }

    function _approvedRemoveContracts(address to) external onlyOwner {
        approvedContracts[to] = false;
    }

    function _approvedContracts(address to) external onlyOwner {
        approvedContracts[to] = true;
    }

    function _getApprovedContracts(address to) public view returns (bool) {
        return approvedContracts[to];
    }

    function _approvedAdmins(address to) external onlyOwner {
        approvedAdmins[to] = true;
    }

    function _getApprovedAdmins(address to) public view returns (bool) {
        return approvedAdmins[to];
    }

    function _ownerOrAdmin() private view
    {
        require(
            msg.sender == owner() || _getApprovedAdmins(msg.sender),
            "Not admin"
        );
    }
    modifier ownerOrAdmin {
        _ownerOrAdmin();
        _;
    }

    function _ownerOrApproved() private view
    {
        require(
            msg.sender == owner() || _getApprovedContracts(msg.sender),
            "Not approved"
        );
    }
    modifier ownerOrApproved {
        _ownerOrApproved();
        _;
    }

    function setPenalty(uint256 _penalty)
        external
        ownerOrApproved
    {
        penalty = _penalty;
    }

    function setBeneficiaryAddress(address payable _factoryBeneficiary)
        external
        onlyOwner
    {
        factoryBeneficiary = _factoryBeneficiary;
    }

    function setGameFundAddress(address payable _gameFund)
        external
        onlyOwner
    {
        gameFund = _gameFund;
    }

    function _setTableContractAddress(TableNFTDetail[] calldata tables, uint256[] calldata rarities)
        external
        ownerOrAdmin
    {
        require(tables.length == rarities.length, "invalid size");

        for(uint256 i = 0; i < tables.length; i++) {
            tablesContractsByRarity[rarities[i]] = tables[i];
        }
    }

    function transferBNBtoUser(address to, uint256 amount) internal {
        userBalance[to].BNB = userBalance[to].BNB.add(amount);
    }

    function transferFTCtoUser(address to, uint256 amount) internal {
        userBalance[to].FTC = userBalance[to].FTC.add(amount);
    }

    function depositBNB() payable external {
        require(msg.value > 0, "Fail send BNB");
        transferBNBtoUser(msg.sender, msg.value);
    }

    function depositFTC(uint256 amount) external {
        require(amount > 0, "Fail send BNB");
        require(IERC20(FTCtoken).allowance(msg.sender, address(this)) >= amount, "Low allowance");
        require(IERC20(FTCtoken).balanceOf(msg.sender) >= amount, "Low FTC");
        require(IERC20(FTCtoken).transferFrom(msg.sender, address(this), amount), "Fail send FTC");
        transferFTCtoUser(msg.sender, amount);
    }

    function withdrawBNB(uint256 amount) public {
        require(userBalance[msg.sender].BNB >= amount, "not enough BNB");
        (bool success, ) = payable(msg.sender).call{
            value: amount,
            gas: 3000000
        }("");
        if(success) {
            userBalance[msg.sender].BNB = userBalance[msg.sender].BNB.sub(amount);
        }
    }

    function withdrawFTC(uint256 amount) public {
        require(userBalance[msg.sender].FTC >= amount, "not enough FTC");
        IERC20(FTCtoken).transfer(msg.sender, amount);
        userBalance[msg.sender].FTC = userBalance[msg.sender].FTC.sub(amount);
    }

    function withdrawAllFunds() external {
        withdrawBNB(userBalance[msg.sender].BNB);
        withdrawFTC(userBalance[msg.sender].FTC);
    }

    function forwardBNBFundsOwner() external ownerOrAdmin {
        uint256 balance = address(this).balance;
        (bool success, ) = payable(factoryBeneficiary).call{
            value: balance,
            gas: 3000000
        }("");
    }

    function forwardFTCFundsOwner() external ownerOrAdmin {
        uint256 balance = IERC20(FTCtoken).balanceOf(address(this));
        IERC20(FTCtoken).transferFrom(address(this), factoryBeneficiary, balance);
    }

    function forwardBNBFundsOwnerAmount(uint256 amount) external ownerOrAdmin {
        require(address(this).balance >= amount, "low BNB");
        (bool success, ) = payable(factoryBeneficiary).call{
            value: amount,
            gas: 3000000
        }("");
    }

    function forwardFTCFundsOwnerAmount(uint256 amount) external ownerOrAdmin {
        require(IERC20(FTCtoken).balanceOf(address(this)) >= amount, "low FTC");
        IERC20(FTCtoken).transferFrom(address(this), factoryBeneficiary, amount);
    }

    // -- add user funds
    function addUserBNB(address to, uint256 amount) external ownerOrAdmin  {
        userBalance[to].BNB = userBalance[to].BNB.add(amount);
    }
    function addUserFTC(address to, uint256 amount) external ownerOrAdmin  {
        userBalance[to].FTC = userBalance[to].FTC.add(amount);
    }

    // -- remove user with bad behaviour

    function removeUserBNB(address to, uint256 amount) public ownerOrAdmin  {
        if(amount > 0 && userBalance[to].BNB >= amount) {
            userBalance[to].BNB = userBalance[to].BNB.sub(amount);
            transferBNBtoUser(gameFund, amount);
        }
    }
    function removeUserFTC(address to, uint256 amount) public ownerOrAdmin  {
        if(amount > 0 && userBalance[to].FTC >= amount) {
            userBalance[to].FTC = userBalance[to].FTC.sub(amount);
            transferFTCtoUser(gameFund, amount);
        }
    }
    function removeUserAllBNB(address to) external ownerOrAdmin  {
        transferBNBtoUser(gameFund, userBalance[to].BNB);
        userBalance[to].BNB = 0;
    }
    function removeUserAllFTC(address to) external ownerOrAdmin  {
        transferFTCtoUser(gameFund, userBalance[to].FTC);
        userBalance[to].FTC = 0;
    }
    function removeUserAllFunds(address to) external ownerOrAdmin  {
        transferBNBtoUser(gameFund, userBalance[to].BNB);
        transferFTCtoUser(gameFund, userBalance[to].FTC);
        delete userBalance[to];
    }
}