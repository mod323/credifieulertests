// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract CredifiCertificateToken is ERC1155, Ownable {
    uint256 private _currentTokenId;
    mapping(uint256 => string) public certificateReferences;

    event CertificateTokenMinted(
        address indexed to,
        uint256 indexed tokenId,
        string certificateRef,
        uint256 amount
    );

    constructor(string memory baseURI) ERC1155(baseURI) Ownable(msg.sender) {}

    function mintCertificate(
        address to,
        string memory certificateRef,
        uint256 amount
    ) public onlyOwner {
        uint256 tokenId = _currentTokenId++;
        _mint(to, tokenId, amount, "");
        certificateReferences[tokenId] = certificateRef;
        emit CertificateTokenMinted(to, tokenId, certificateRef, amount);
    }
}
