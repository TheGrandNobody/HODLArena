//SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "../interfaces/ITimelock.sol";

/**
 * @title Timelock contract 
 * @author Taken from Compound (COMP) and tweaked/detailed by Nobody (me)
 * @notice A timelock contract queues and executes proposals made through the Eternal Fund contract
 */
 contract Timelock is ITimelock {
    
    // The period of time any proposal action is given to be executed once the queuing period is over
    uint256 public constant GRACE_PERIOD = 14 days;
    // The lower bound for the minimum amount of time the contract must wait before queuing a proposal
    uint256 public constant MINIMUM_DELAY = 2 days;
    // The upper bound for the minimum amount of time the contract must wait before queuing a proposal
    uint256 public constant MAXIMUM_DELAY = 30 days;
    
    // The address of this contract's fund
    address public fund;
    // The address of the next fund (stored here until it accepts the role)
    address public pendingFund;
    // The minimum amount of time the contract must wait before queuing a proposal
    uint256 public delay;
    // Determines whether a given transaction hash is queued or not
    mapping (bytes32 => bool) public queuedTransactions;


    constructor(address _fund, uint256 _delay) {
        require(_delay >= MINIMUM_DELAY, "Delay must exceed minimum delay");
        require(_delay <= MAXIMUM_DELAY, "Delay can't exceed maximum delay");

        fund = _fund;
        delay = _delay;
    }

    // Fallback function
    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}

    /**
     * @notice Updates the amount of time the contract must wait before queuing a proposal
     * @param _delay The new value of the delay
     * 
     * Requirements:
     *
     * - Only callable by this contract
     * - The new delay value cannot be inferior to its lower bound
     * - The new delay value cannot exceed its upper bound
     */
    function setDelay(uint256 _delay) public {
        require(msg.sender == address(this), "Call must come from Timelock");
        require(_delay >= MINIMUM_DELAY, "Delay must exceed minimum delay");
        require(_delay <= MAXIMUM_DELAY, "Delay can't exceed maximum delay");
        delay = _delay;

        emit NewDelay(delay);
    }

    /**
     * @notice Accepts the offer of having the admin role
     * 
     * Requirements:
     *
     * - Only callable by an an address who was offered the role of fund
     */
    function acceptFund() public {
        require(msg.sender == pendingFund, "Only callable by a pending Fund");
        fund = msg.sender;
        pendingFund = address(0);

        emit NewAdmin(fund);
    }

    /**
     * @notice Offers the role of admin to a given user
     * @param _pendingFund The address of the specified user
     * 
     * Requirements:
     *
     * - Only callable by this contract
     */
    function setPendingAdmin(address _pendingFund) public {
        require(msg.sender == address(this), "Call must come from Timelock");
        pendingFund = _pendingFund;

        emit NewPendingAdmin(pendingFund);
    }

    /**
     * @notice Queues a given proposal's action
     * @param target The address of the contract whose function is being called
     * @param value The amount of AVAX being transferred in this transaction
     * @param signature The function signature of this proposal's action
     * @param data The function parameters of this proposal's action
     * @param eta The estimated minimum UNIX time (in seconds) at which this transaction is to be executed 
     * @return The transaction hash of this proposal's action
     * 
     * Requirements:
     *
     * - Only callable by the fund
     * - The estimated time of action must be greater than or equal to the minimum delay time
     */
    function queueTransaction(address target, uint256 value, string memory signature, bytes memory data, uint256 eta) public returns (bytes32) {
        require(msg.sender == fund, "Call must come from the fund");
        require(eta >= block.timestamp + delay, "Delay is not over yet");

        bytes32 txHash = keccak256(abi.encode(target, value, signature, data, eta));
        queuedTransactions[txHash] = true;

        emit QueueTransaction(txHash, target, value, signature, data, eta);
        return txHash;
    }

    /**
     * @notice Dequeues a given proposal's action
     * @param target The address of the contract whose function is being called
     * @param value The amount of AVAX being transferred in this transaction
     * @param signature The function signature of this proposal's action
     * @param data The function parameters of this proposal's action
     * @param eta The estimated minimum UNIX time (in seconds) at which this transaction is to be executed 
     * 
     * Requirements:
     *
     * - Only callable by the fund
     */
    function cancelTransaction(address target, uint256 value, string memory signature, bytes memory data, uint256 eta) public {
        require(msg.sender == fund, "Call must come from the fund");

        bytes32 txHash = keccak256(abi.encode(target, value, signature, data, eta));
        queuedTransactions[txHash] = false;

        emit CancelTransaction(txHash, target, value, signature, data, eta);
    }

    /**
     * @notice Executes a given proposal's action
     * @param target The address of the contract whose function is being called
     * @param value The amount of AVAX being transferred in this transaction
     * @param signature The function signature of this proposal's action
     * @param data The function parameters of this proposal's action
     * @param eta The estimated minimum UNIX time (in seconds) at which this transaction is to be executed 
     * @return The variable returned from executing the function call
     * 
     * Requirements:
     *
     * - Only callable by the fund
     * - The transaction must be in the queue
     * - The delay period of execution must be over
     * - The transaction must be executed within the grace period
     */
    function executeTransaction(address target, uint256 value, string memory signature, bytes memory data, uint256 eta) public payable returns (bytes memory) {
        require(msg.sender == fund, "Call must come from the fund");

        bytes32 txHash = keccak256(abi.encode(target, value, signature, data, eta));
        require(queuedTransactions[txHash], "Transaction hasn't been queued");
        require(block.timestamp >= eta, "Transaction delay not over");
        require(block.timestamp <= eta + GRACE_PERIOD, "Transaction is stale");

        queuedTransactions[txHash] = false;

        bytes memory callData;

        if (bytes(signature).length == 0) {
            callData = data;
        } else {
            callData = abi.encodePacked(bytes4(keccak256(bytes(signature))), data);
        }

        (bool success, bytes memory returnData) = target.call{value: value}(callData);
        require(success, "Transaction execution reverted");

        emit ExecuteTransaction(txHash, target, value, signature, data, eta);

        return returnData;
    }
}