// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

/* Signature Verification

How to Sign and Verify
# Signing
1. Create message to sign
2. Hash the message
3. Sign the hash (off chain, keep your private key secret)

# Verify
1. Recreate hash from the original message
2. Recover signer from signature and hash
3. Compare recovered signer to claimed signer
*/

contract VerifySignature is IERC721Receiver, Pausable, Ownable{
    using SafeMath for uint256;
    
    mapping(string => address) private NFTaddress;
    mapping(address => bool) private approvedContracts;
	mapping(string => mapping ( uint => address)) private NFTowner;
    mapping(address => uint256) private nonce;
    mapping(address => uint256) private nonceMin;
    mapping(address => uint256) private nonceMax;

    event Signature(address _signer, uint256 tokenId, string _type, bytes signature, bytes32 messageHash, bytes32 ethSignedMessageHash, address result, uint nonce);
    event NewNonce(uint256 minNonce, uint256 maxNonce, uint256 nonce, uint256 maxN);

    constructor() {
    }

    function onERC721Received(address, address, uint256, bytes memory) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
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

    function setNFTaddress(string memory _type, address addr) public onlyOwner {
        NFTaddress[_type] = addr;
    }

    function generateNewNonce(address user) internal  {
        require(msg.sender == user, 'Only user can see the nonce!');

        if(nonceMax[user] == 0) {
            nonceMax[user] = 105;
        }
        if(nonceMin[user] == 0) {
            nonceMin[user] = 27;
        }
        uint256 maxN = nonceMax[user].sub(nonceMin[user]);
        uint256 newNonce = uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty, msg.sender))) % maxN;
        newNonce = newNonce.add(nonceMin[user]);

        nonceMax[user] = nonceMax[user].add(newNonce);
        nonceMin[user] = nonceMin[user].add(maxN);
        
        nonce[user] = newNonce;

        emit NewNonce(nonceMin[user], nonceMax[user], nonce[user], maxN);
    }

    function getMessageHash(
        address _signer,
        string memory _random,
        string memory _type,
        uint256 _tokenId,
        uint _nonce
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_signer, _random, _type, _tokenId, _nonce));
    }

    function getEthSignedMessageHash(bytes32 _messageHash)
        internal
        pure
        returns (bytes32)
    {
        return
            keccak256(
                abi.encodePacked("\x19Ethereum Signed Message:\n32", _messageHash)
            );
    }

    function getNonce(
        address user
    ) public whenNotPaused() view returns (uint256) {
        require(msg.sender == user, 'Only user can see the nonce!');

        return nonce[user];
    }

    function setNFTowner(
        address _signer,
        uint256 _tokenId,
        string memory _type
    ) public whenNotPaused() {
        require(_getApprovedContracts(msg.sender),'Only Approver!');

        NFTowner[_type][_tokenId] = _signer;
    } 

    function verify(
        address _signer,
        uint256 _tokenId,
        string memory _type,
        string memory _random,
        bytes memory signature
    ) public whenNotPaused() returns (bool){
        uint AddrNonce = getNonce(_signer); //check nonce - only signer
        bytes32 messageHash = getMessageHash(_signer, _random, _type, _tokenId, AddrNonce);
        bytes32 ethSignedMessageHash = getEthSignedMessageHash(messageHash);
        address resultSignAddress = recoverSigner(ethSignedMessageHash, signature);

        if( address(resultSignAddress) == address(_signer)) { //check signature
            if(msg.sender == _signer) { //check msg sender 
                emit Signature(_signer, _tokenId, _type, signature, messageHash, ethSignedMessageHash, resultSignAddress, AddrNonce);

                generateNewNonce(_signer);

                address nftAddress = getNFTaddress(_type);
                if(nftAddress != address(0)) {
                    if(NFTowner[_type][_tokenId] != address(0)) { //check tokenId owner
                        IERC721(nftAddress).safeTransferFrom(address(this), _signer, _tokenId);
                        NFTowner[_type][_tokenId] = address(0);

                        return true;
                    } else {
                        return false;
                    }
                } else {
                    return false;
                }
            } else {
                return false;
            }
        } else {
            return false;
        }
    }

    function typeLength(string memory s) public pure returns ( uint256) {
        return bytes(s).length;
    }

    function getNFTaddress(string memory _type) view internal returns (address) {
        require(typeLength(_type) > 0, 'NFT type cannot be empty!');
        
        return NFTaddress[_type];
    }

    function transferNFTapprover(address to, uint256 tokenId, string memory _type) public {
        require(_getApprovedContracts(msg.sender),'Only Approver!');

        address nftAddress = getNFTaddress(_type);
        IERC721(nftAddress).safeTransferFrom(address(this), to, tokenId);
    }

    function recoverSigner(bytes32 _ethSignedMessageHash, bytes memory _signature)
        public
        pure
        returns (address)
    {
        (bytes32 r, bytes32 s, uint8 v) = splitSignature(_signature);

        return ecrecover(_ethSignedMessageHash, v, r, s);
    }

    function splitSignature(bytes memory sig)
        public
        pure
        returns (
            bytes32 r,
            bytes32 s,
            uint8 v
        )
    {
        require(sig.length == 65, "invalid signature length");

        assembly {
            /*
            First 32 bytes stores the length of the signature

            add(sig, 32) = pointer of sig + 32
            effectively, skips first 32 bytes of signature

            mload(p) loads next 32 bytes starting at the memory address p into memory
            */

            // first 32 bytes, after the length prefix
            r := mload(add(sig, 32))
            // second 32 bytes
            s := mload(add(sig, 64))
            // final byte (first byte of the next 32 bytes)
            v := byte(0, mload(add(sig, 96)))
        }

        // implicitly return (r, s, v)
    }
}