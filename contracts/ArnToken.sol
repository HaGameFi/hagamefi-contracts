// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./ERC20.sol";

contract ArnToken is ERC20, Ownable {
    using SafeMath for uint256;

    /**
     * The time interval from each 'mint' to the 'Arn mining pool' is not less than 365 days
     */
    uint256 public constant  MINT_INTERVAL = 365 days;

    /**
     * All of the minted 'Arn' will be moved to the mainPool.
     */
    address public mainPool;

    /**
     * The unix Timestamp for the latest mint.
     */
    uint256 public latestMinting;

    /**
     * All of the minted 'Mbox' burned in the corresponding mining pool if the released amount is not used up in the current year
     *
     */
    uint256[6] public maxMintOfYears;

    /**
     * The number of times 'mint' has been executed
     */
    uint256 public yearMint = 0;

    constructor()
    public
    ERC20("HeroArena", "Arn", 18)
    {
        maxMintOfYears[0] = 400000000 * 10 ** uint256(decimals);
        maxMintOfYears[1] = 225000000 * 10 ** uint256(decimals);
        maxMintOfYears[2] = 175000000 * 10 ** uint256(decimals);
        maxMintOfYears[3] = 125000000 * 10 ** uint256(decimals);
        maxMintOfYears[4] = 75000000  * 10 ** uint256(decimals);
        maxMintOfYears[5] = 50000000  * 10 ** uint256(decimals);
    }

    /**
     * The unix Timestamp of 'mint' can be executed next time
     */
    function nextMinting() public view returns(uint256) {
        return latestMinting + MINT_INTERVAL;
    }

    /**
     * Set the target mining pool contract for minting
     */
    function setMainPool(address pool_) external onlyOwner {
        require(pool_ != address(0));
        mainPool = pool_;
    }

    /**
     * Distribute MBOX to the main mining pool according to the MBOX limit that can be released every year
     */
    function mint(address dest_) external {
        require(msg.sender == mainPool, "invalid minter");
        require(latestMinting.add(MINT_INTERVAL) < block.timestamp, "minting not allowed yet");

        uint256 amountThisYear = yearMint < 5 ? maxMintOfYears[yearMint] : maxMintOfYears[5];
        yearMint += 1;
        latestMinting = block.timestamp;

        _mint(dest_, amountThisYear);
    }

    function burn(uint256 amount_) external {
        _burn(msg.sender, amount_);
    }

    function burnFrom(address from_, uint256 amount_) external {
        require(from_ != address(0), "burn from zero");

        _approve(from_, msg.sender, _allowances[from_][msg.sender].sub(amount_));
        _burn(from_, amount_);
    }
}