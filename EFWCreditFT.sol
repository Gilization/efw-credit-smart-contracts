// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

contract EFWCreditFT {
    // === ERC20 Metadata ===
    string public name = "EFW Credit";
    string public symbol = "EFWC";
    uint8 public immutable decimals = 18; 

    // === ERC20 Storage ===
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // === Roles & Wiring ===
    address public tokenMaker;   
    address public redemption;   

    // === Donation Registry + FIFO ===
    struct DonationEntry {
        uint256 donationId;
        uint256 remainingFaceValue; 
        bool exists;
        bool minted;                
    }
    mapping(uint256 => DonationEntry) public donations;
    uint256[] public donationQueue; 
    uint256 public fifoHead;        

    // === Events ===
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    event TokenMakerUpdated(address indexed newMaker);
    event RedemptionContractUpdated(address indexed newRedemption);

    event DonationAuthorized(uint256 indexed donationId, uint256 faceValue);
    event TokensMinted(uint256 indexed donationId, address indexed recipient, uint256 faceValue);
    event TokensDistributed(address indexed from, address indexed to, uint256 amount);

    event CreditRedeemedFIFO(
        address indexed claimer,
        uint256 amount,
        bytes32 compositionHash,
        uint256[] donationIds,
        uint256[] parts
    ); 

    // === Access Control ===
    modifier onlyTokenMaker() {
        require(msg.sender == tokenMaker, "Not tokenMaker");
        _;
    }
    modifier onlyRedemption() {
        require(msg.sender == redemption, "Not redemption");
        _;
    }

    constructor() {
        tokenMaker = msg.sender;
        emit TokenMakerUpdated(msg.sender);
    }

    // --- Admin wiring ---
    function setTokenMaker(address _maker) external onlyTokenMaker {
        require(_maker != address(0), "maker=0");
        tokenMaker = _maker;
        emit TokenMakerUpdated(_maker);
    }

    function setRedemption(address _redemption) external onlyTokenMaker {
        require(_redemption != address(0), "redemption=0");
        redemption = _redemption;
        emit RedemptionContractUpdated(_redemption);
    }

    // --- ERC20 core ---
    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= amount, "allowance");
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - amount;
            emit Approval(from, msg.sender, allowance[from][msg.sender]);
        }
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(to != address(0), "to=0");
        uint256 bal = balanceOf[from];
        require(bal >= amount, "insufficient");
        unchecked { balanceOf[from] = bal - amount; }
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        emit TokensDistributed(from, to, amount);
    }

    function _mint(address to, uint256 amount) internal {
        require(to != address(0), "to=0");
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    // === SC-1 Business ===

    /// @notice 
    
    function authorizeDonation(uint256 donationId, uint256 faceValue) external onlyTokenMaker {
        require(donationId != 0, "donationId=0");
        require(faceValue > 0, "face=0");
        DonationEntry storage d = donations[donationId];
        require(!d.exists, "already authz");

        d.donationId = donationId;
        d.remainingFaceValue = faceValue;
        d.exists = true;
        d.minted = false;

        donationQueue.push(donationId);
        emit DonationAuthorized(donationId, faceValue);
    }

    /// @notice
    
    function mintToRecipient(uint256 donationId, address recipient) external onlyTokenMaker {
        DonationEntry storage d = donations[donationId];
        require(d.exists, "not authz");
        require(!d.minted, "already minted");
        uint256 amount = d.remainingFaceValue;
        require(amount > 0, "face=0");

        d.minted = true;
        _mint(recipient, amount);
        emit TokensMinted(donationId, recipient, amount);
    }

function burnWithFIFO(address from, uint256 amount)
    external
    onlyRedemption
    returns (uint256[] memory donationIds, uint256[] memory parts)
{
    require(amount > 0, "amount=0");

    // Burn balance from 'from'
    uint256 bal = balanceOf[from];
    require(bal >= amount, "balance");
    unchecked { balanceOf[from] = bal - amount; }
    totalSupply -= amount;
    emit Transfer(from, address(0), amount);

    // Allocate against FIFO registry
    uint256 remaining = amount;

    donationIds = new uint256[](donationQueue.length);
    parts       = new uint256[](donationQueue.length);
    uint256 idx = 0;

    while (remaining > 0 && fifoHead < donationQueue.length) {
        uint256 did = donationQueue[fifoHead];
        DonationEntry storage d = donations[did];

        if (!d.exists || d.remainingFaceValue == 0) {
            fifoHead += 1; 
            continue;
        }

        uint256 take = d.remainingFaceValue > remaining ? remaining : d.remainingFaceValue;
        d.remainingFaceValue -= take;
        remaining -= take;

        donationIds[idx] = did;
        parts[idx] = take;
        idx++;

        if (d.remainingFaceValue == 0) {
            fifoHead += 1; 
        }
    }

    require(remaining == 0, "insufficient FIFO pool");

    
    assembly {
        mstore(donationIds, idx)
        mstore(parts, idx)
    }

    bytes32 compositionHash = keccak256(abi.encode(donationIds, parts));
    emit CreditRedeemedFIFO(from, amount, compositionHash, donationIds, parts);

    return (donationIds, parts);
}

}
