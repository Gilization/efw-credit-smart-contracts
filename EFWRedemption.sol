// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// === OpenZeppelin ===
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

// Interface ke SC-1 (EFWCreditFT)
interface IEfwFt {
    function balanceOf(address) external view returns (uint256);
    function burnWithFIFO(address from, uint256 amount)
        external
        returns (uint256[] memory donationIds, uint256[] memory parts);
}

contract EFWRedemption is ERC721 {
    using Strings for uint256;

    // --- Roles ---
    address public tokenMaker;
    modifier onlyTokenMaker() {
        require(msg.sender == tokenMaker, "Not tokenMaker");
        _;
    }

    // --- FT handle ---
    IEfwFt public ft;

    // --- NFT meta ---
    uint256 public totalSupply;
    uint256 private _nextTokenId; 

    string private _baseTokenURI;

    function setBaseURI(string calldata newBase) external onlyTokenMaker {
        _baseTokenURI = newBase;
    }

    struct Cert {
        uint256 value;
        bytes32 compositionHash;
        uint256 redeemedAt;
        address claimer;
    }

    mapping(uint256 => Cert) public certMeta;
    mapping(address => uint256[]) private _ownedTokens;

    event CertificateIssued(address indexed claimer, uint256 indexed tokenId, uint256 value, bytes32 compositionHash);
    event TokenMakerUpdated(address indexed newMaker);

    constructor(address ftAddr, address tokenMakerAddr)
        ERC721("EFW Certificate", "EFWCert")
    {
        require(ftAddr != address(0) && tokenMakerAddr != address(0), "zero");
        ft = IEfwFt(ftAddr);
        tokenMaker = tokenMakerAddr;
        emit TokenMakerUpdated(tokenMakerAddr);
    }

    function setTokenMaker(address m) external onlyTokenMaker {
        require(m != address(0), "zero");
        tokenMaker = m;
        emit TokenMakerUpdated(m);
    }

    // --- Non-transferable guards (OZ v5 style) ---
    function _update(address to, uint256 tokenId, address auth)
        internal
        override
        returns (address)
    {
        if (_ownerOf(tokenId) == address(0) && to != address(0)) {
            return super._update(to, tokenId, auth);
        }
        revert("non-transferable");
    }

    function _approve(
        address,
        uint256,
        address,
        bool
    )
        internal
        pure
        override
    {
        revert("non-transferable");
    }

    function _setApprovalForAll(
        address,
        address,
        bool
    )
        internal
        pure
        override
    {
        revert("non-transferable");
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "URI query for nonexistent token");
        string memory base = _baseURI();
        if (bytes(base).length == 0) return "";
        return string(abi.encodePacked(base, tokenId.toString()));
    }

    function getCertificate(uint256 tokenId) external view returns (Cert memory) {
        return certMeta[tokenId];
    }

    function certsOf(address owner) external view returns (uint256[] memory) {
        return _ownedTokens[owner];
    }

    function validateAndRedeem(address claimer, uint256 amount)
        external
        onlyTokenMaker
        returns (uint256 tokenId, bytes32 compositionHash)
    {
        require(claimer != address(0), "claimer=0");
        require(amount > 0, "amount=0");
        require(ft.balanceOf(claimer) >= amount, "balance");

        (uint256[] memory donationIds, uint256[] memory parts) = ft.burnWithFIFO(claimer, amount);

        compositionHash = keccak256(abi.encode(donationIds, parts));

        tokenId = _mintCertificate(claimer, amount, compositionHash);
    }

    function _mintCertificate(address to, uint256 value, bytes32 ch)
        internal
        returns (uint256 tokenId)
    {
        require(to != address(0), "to=0");

        _nextTokenId++;                 
        tokenId = _nextTokenId;         
        _safeMint(to, tokenId);         

        certMeta[tokenId] = Cert({
            value: value,
            compositionHash: ch,
            redeemedAt: block.timestamp,
            claimer: to
        });

        _ownedTokens[to].push(tokenId);
        totalSupply += 1;

        emit CertificateIssued(to, tokenId, value, ch);
    }
}