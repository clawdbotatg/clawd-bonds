// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title ClaWDBonds
 * @notice Lock CLAWD tokens for a fixed term, earn rewards from a pre-funded treasury.
 * @dev Two bond terms: 24hr (0.5%) and 7day (2%). Treasury-funded, capped by available rewards.
 */
contract ClaWDBonds is Ownable {
    using SafeERC20 for IERC20;
    IERC20 public immutable clawdToken;

    struct BondTerm {
        uint256 duration;
        uint256 rewardRate; // basis points (50 = 0.5%, 200 = 2%)
    }

    struct Bond {
        address user;
        uint256 amount;
        uint256 reward;
        uint256 maturityTimestamp;
        bool claimed;
    }

    uint256 public bondCounter;
    uint256 public totalTreasuryFunded;
    uint256 public totalRewardsCommitted;

    mapping(uint256 => Bond) public bonds;
    mapping(address => uint256[]) public userBonds;
    BondTerm[2] public bondTerms;

    event TreasuryFunded(address indexed funder, uint256 amount, uint256 newTotal);
    event BondCreated(address indexed user, uint256 indexed bondId, uint256 amount, uint256 reward, uint8 termIndex, uint256 maturity);
    event BondClaimed(address indexed user, uint256 indexed bondId, uint256 principal, uint256 reward);
    event TreasuryWithdrawn(address indexed owner, uint256 amount);

    error InsufficientTreasuryBalance();
    error InvalidTermIndex();
    error BondNotMatured();
    error BondAlreadyClaimed();
    error BondNotExists();
    error NotBondOwner();
    error InsufficientWithdrawableBalance();
    error ZeroAmount();

    constructor(address _clawdToken, address _initialOwner) Ownable(_initialOwner) {
        require(_clawdToken != address(0), "Invalid token address");
        clawdToken = IERC20(_clawdToken);
        bondTerms[0] = BondTerm({ duration: 24 hours, rewardRate: 50 });
        bondTerms[1] = BondTerm({ duration: 7 days, rewardRate: 200 });
    }

    function fundTreasury(uint256 amount) external onlyOwner {
        if (amount == 0) revert ZeroAmount();
        clawdToken.safeTransferFrom(msg.sender, address(this), amount);
        totalTreasuryFunded += amount;
        emit TreasuryFunded(msg.sender, amount, totalTreasuryFunded);
    }

    function createBond(uint256 amount, uint8 termIndex) external returns (uint256 bondId) {
        if (amount == 0) revert ZeroAmount();
        if (termIndex >= 2) revert InvalidTermIndex();
        BondTerm memory term = bondTerms[termIndex];
        uint256 reward = (amount * term.rewardRate) / 10000;
        if (availableTreasury() < reward) revert InsufficientTreasuryBalance();
        clawdToken.safeTransferFrom(msg.sender, address(this), amount);
        bondId = ++bondCounter;
        bonds[bondId] = Bond({
            user: msg.sender,
            amount: amount,
            reward: reward,
            maturityTimestamp: block.timestamp + term.duration,
            claimed: false
        });
        userBonds[msg.sender].push(bondId);
        totalRewardsCommitted += reward;
        emit BondCreated(msg.sender, bondId, amount, reward, termIndex, block.timestamp + term.duration);
    }

    function claimBond(uint256 bondId) external {
        Bond storage bond = bonds[bondId];
        if (bond.user == address(0)) revert BondNotExists();
        if (bond.user != msg.sender) revert NotBondOwner();
        if (block.timestamp < bond.maturityTimestamp) revert BondNotMatured();
        if (bond.claimed) revert BondAlreadyClaimed();
        bond.claimed = true;
        totalRewardsCommitted -= bond.reward;
        totalTreasuryFunded -= bond.reward;
        clawdToken.safeTransfer(bond.user, bond.amount + bond.reward);
        emit BondClaimed(bond.user, bondId, bond.amount, bond.reward);
    }

    function withdrawTreasury(uint256 amount) external onlyOwner {
        if (amount == 0) revert ZeroAmount();
        if (amount > availableTreasury()) revert InsufficientWithdrawableBalance();
        totalTreasuryFunded -= amount;
        clawdToken.safeTransfer(owner(), amount);
        emit TreasuryWithdrawn(owner(), amount);
    }

    function getBond(uint256 bondId) external view returns (Bond memory) {
        return bonds[bondId];
    }

    function getUserBonds(address user) external view returns (uint256[] memory) {
        return userBonds[user];
    }

    function availableTreasury() public view returns (uint256) {
        return totalTreasuryFunded >= totalRewardsCommitted
            ? totalTreasuryFunded - totalRewardsCommitted
            : 0;
    }

    function getBondTerm(uint8 termIndex) external view returns (BondTerm memory) {
        if (termIndex >= 2) revert InvalidTermIndex();
        return bondTerms[termIndex];
    }

    function getBondTermsCount() external pure returns (uint256) {
        return 2;
    }

    function isBondClaimable(uint256 bondId) external view returns (bool) {
        Bond storage bond = bonds[bondId];
        return bond.user != address(0) && !bond.claimed && block.timestamp >= bond.maturityTimestamp;
    }

    function getContractStats()
        external
        view
        returns (uint256 totalTreasury, uint256 available, uint256 committed, uint256 totalBonds)
    {
        return (totalTreasuryFunded, availableTreasury(), totalRewardsCommitted, bondCounter);
    }
}
