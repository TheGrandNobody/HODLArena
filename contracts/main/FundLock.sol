pragma solidity ^0.8.0;

import "../inheritances/OwnableEnhanced.sol";
import "../interfaces/IEternalToken.sol";

/**
 * @title FundLock contract
 * @author Nobody (me)
 * @notice The FundLock contract holds the funds earned from the (initially) 1% fee until the Eternal Fund contract is released (2.5 months)
 */
contract FundLock is OwnableEnhanced {
    // The Eternal Token interface
    IEternalToken eternal;

    // Keeps track of how much time has elapsed before the funds
    uint256 timeOfRelease;


    constructor (address _eternal) {
        eternal = IEternalToken(_eternal);
        timeOfRelease = block.timestamp + 6574500;
    }

    /**
     * @dev Withraws locked funds to the Eternal Fund if 2.5 months have elapsed since deployment.
     */
    function withdrawFunds() external onlyAdminAndFund() {
        require(block.timestamp <= timeOfRelease, "Funds are still locked");

        eternal.transfer(fund(), eternal.balanceOf(address(this)));
    }
}