# YieldAggregator

A robust Clarity smart contract for decentralized yield farming aggregation on the Stacks blockchain, enabling users to stake tokens across multiple pools and earn rewards.

## Table of Contents

  * Features
  * Contract Overview
      * Constants & Variables
      * Data Maps
      * Private Functions
      * Public Functions
      * Read-Only Functions
  * How It Works
      * Creating a Pool
      * Staking Tokens
      * Unstaking Tokens
      * Claiming Rewards
      * Batch Claiming Rewards
      * Portfolio Summary
  * Errors
  * Usage
  * Development & Testing
  * Contributing
  * License

-----

## Features

  * **Multi-Pool Yield Farming:** Supports the creation and management of multiple yield farming pools, each with distinct token and reward token principals.
  * **Dynamic Reward Calculation:** Rewards are calculated per block, ensuring fairness and real-time accrual based on staked amounts and pool-specific reward rates.
  * **Protocol Fees:** A configurable protocol fee is applied to claimed rewards, directed to a designated fee collector.
  * **Flexible Staking/Unstaking:** Users can stake new amounts or partially/fully unstake their existing positions.
  * **Batch Operations:** Enables users to claim rewards from multiple pools simultaneously for enhanced efficiency.
  * **Advanced Portfolio Analytics:** Provides a comprehensive summary of a user's total staked value, pending rewards, and portfolio diversification across up to 5 pools.
  * **Owner-Controlled Pool Creation:** Only the contract owner can create new farming pools, ensuring controlled growth and management.

-----

## Contract Overview

The `YieldAggregator` contract manages staking pools, user positions, and reward distribution. It prioritizes clarity, security, and efficiency in its operations.

### Constants & Variables

  * `CONTRACT-OWNER`: The principal of the contract deployer, holding administrative privileges.
  * `ERR-OWNER-ONLY` (u100): Returned if a function requiring owner permissions is called by a non-owner.
  * `ERR-NOT-FOUND` (u101): Returned if a specified pool or user position does not exist.
  * `ERR-INVALID-AMOUNT` (u102): Returned for invalid input amounts (e.g., zero stake, stake below minimum).
  * `ERR-INSUFFICIENT-BALANCE` (u103): Returned if a user attempts to unstake more than their staked amount.
  * `ERR-POOL-INACTIVE` (u104): Returned if an operation is attempted on an inactive pool.
  * `ERR-ALREADY-EXISTS` (u105): Reserved for future use; currently not explicitly used in an `asserts!`.
  * `MIN-DEPOSIT` (u1000000): The minimum allowed deposit amount (1 token, assuming 6 decimals).
  * `PRECISION` (u1000000): Used for fixed-point arithmetic, representing 6 decimal places.
  * `pool-counter` (uint): Increments with each new pool created, providing unique `pool-id`s.
  * `total-pools` (uint): Tracks the total number of active pools.
  * `protocol-fee-rate` (uint): The percentage of claimed rewards taken as a fee, in basis points (e.g., u250 = 2.5%).
  * `fee-collector` (principal): The address where protocol fees are sent.

### Data Maps

  * `pools`:
      * Key: `{ pool-id: uint }`
      * Value: `{ token-contract: principal, reward-token: principal, total-staked: uint, reward-rate: uint, last-update-block: uint, accumulated-reward-per-token: uint, is-active: bool, min-stake: uint }`
      * Stores all configurations and state for each farming pool.
  * `user-positions`:
      * Key: `{ user: principal, pool-id: uint }`
      * Value: `{ amount: uint, reward-debt: uint, last-claim-block: uint, entry-block: uint }`
      * Records each user's staked amount, their reward debt (a snapshot of `accumulated-reward-per-token` at the time of their last interaction for accurate reward calculation), the block of their last claim, and the block they first entered the pool.
  * `user-pool-count`:
      * Key: `{ user: principal }`
      * Value: `{ count: uint }`
      * Keeps a tally of how many unique pools a user has active positions in.

### Private Functions

  * `(is-contract-owner)`: Checks if `tx-sender` is the `CONTRACT-OWNER`.
  * `(calculate-pending-rewards (user principal) (pool-id uint))`: Computes the pending rewards for a specific user in a given pool. It uses the `accumulated-reward-per-token` from the pool and the user's `reward-debt` to determine the difference, scaled by their staked amount.
  * `(update-pool-rewards (pool-id uint))`: Updates the `accumulated-reward-per-token` for a given pool based on the time elapsed and the pool's `reward-rate`. This function is called before staking or claiming to ensure reward calculations are current.
  * `(calculate-protocol-fee (amount uint))`: Calculates the fee amount based on the `protocol-fee-rate` and the given `amount`.
  * `(get-user-pool-data (user principal) (pool-id uint))`: A helper function for the portfolio summary that retrieves a user's staked amount, pending rewards, and whether they have an active position in a specific pool.
  * `(claim-single-pool-rewards (pool-id uint))`: A wrapper function for `claim-rewards` used specifically by `batch-claim-rewards` to handle individual pool claims and return the claimed amount.
  * `(sum-claimed-rewards (reward-amount uint) (total uint))`: A reducer function used in `batch-claim-rewards` to sum up the rewards claimed from individual pools.

### Public Functions

  * `(create-pool (token-contract principal) (reward-token principal) (reward-rate uint) (min-stake uint))`:
      * **Description:** Allows the `CONTRACT-OWNER` to create a new yield farming pool.
      * **Parameters:**
          * `token-contract`: The principal of the token users will stake.
          * `reward-token`: The principal of the token distributed as rewards.
          * `reward-rate`: The rate at which rewards are generated per block per unit of staked token.
          * `min-stake`: The minimum amount a user must stake to participate in this pool.
      * **Returns:** `(ok uint)` the new `pool-id` or an error.
  * `(stake-tokens (pool-id uint) (amount uint))`:
      * **Description:** Allows a user to stake `amount` of tokens into a specified pool.
      * **Parameters:**
          * `pool-id`: The ID of the pool to stake in.
          * `amount`: The quantity of tokens to stake.
      * **Returns:** `(ok { staked: uint, pending-rewards: uint })` with the amount staked and any pending rewards before the new stake, or an error.
  * `(unstake-tokens (pool-id uint) (amount uint))`:
      * **Description:** Allows a user to unstake `amount` of tokens from a specified pool and claim their accrued rewards.
      * **Parameters:**
          * `pool-id`: The ID of the pool to unstake from.
          * `amount`: The quantity of tokens to unstake.
      * **Returns:** `(ok { unstaked: uint, rewards-claimed: uint, protocol-fee: uint })` with the amount unstaked, rewards claimed, and protocol fee, or an error.
  * `(claim-rewards (pool-id uint))`:
      * **Description:** Allows a user to claim their pending rewards from a specific pool.
      * **Parameters:**
          * `pool-id`: The ID of the pool to claim rewards from.
      * **Returns:** `(ok { rewards-claimed: uint, protocol-fee: uint })` with the rewards claimed and protocol fee, or an error.
  * `(batch-claim-rewards (pool-ids (list 5 uint)))`:
      * **Description:** Allows a user to claim rewards from up to 5 specified pools in a single transaction.
      * **Parameters:**
          * `pool-ids`: A list of `pool-id`s (max 5) from which to claim rewards.
      * **Returns:** `(ok { pools-processed: uint, total-rewards-claimed: uint, individual-results: (list 5 uint) })` with the number of pools processed, total rewards claimed, and individual results from each claim, or an error.

### Read-Only Functions

  * `(get-pool-info (pool-id uint))`:
      * **Description:** Retrieves all information for a specific pool.
      * **Parameters:** `pool-id`: The ID of the pool.
      * **Returns:** `(optional { ...pool-data... })` or `none` if not found.
  * `(get-user-position (user principal) (pool-id uint))`:
      * **Description:** Retrieves a user's staking position in a specific pool.
      * **Parameters:**
          * `user`: The principal of the user.
          * `pool-id`: The ID of the pool.
      * **Returns:** `(optional { ...user-position-data... })` or `none` if not found.
  * `(get-pending-rewards (user principal) (pool-id uint))`:
      * **Description:** Calculates the pending rewards for a user in a particular pool without performing a transaction.
      * **Parameters:**
          * `user`: The principal of the user.
          * `pool-id`: The ID of the pool.
      * **Returns:** `(ok uint)` the amount of pending rewards.
  * `(get-total-pools)`:
      * **Description:** Returns the total number of pools created on the aggregator.
      * **Returns:** `uint`.
  * `(get-user-portfolio-summary (user principal))`:
      * **Description:** Provides an analytical summary of a user's activity across a predefined set of pools (pools 1-5).
      * **Parameters:** `user`: The principal of the user.
      * **Returns:** `(ok { user: principal, total-staked-value: uint, total-pending-rewards: uint, active-positions: uint, average-reward-rate: uint, portfolio-health: (string-ascii 12) })`.
          * `total-staked-value`: Sum of all staked tokens across specified pools.
          * `total-pending-rewards`: Sum of all pending rewards across specified pools.
          * `active-positions`: Count of pools where the user has a stake.
          * `average-reward-rate`: A calculated average of rewards per token across active pools.
          * `portfolio-health`: A simple indicator ("diversified" if \>2 active positions, "concentrated" otherwise).

-----

## How It Works

This section details the primary interactions with the `YieldAggregator` contract.

### Creating a Pool

The contract owner initiates new yield farming opportunities by calling `create-pool`. They define the tokens involved, the reward rate, and the minimum stake required for the new pool.

### Staking Tokens

Users stake their tokens by calling `stake-tokens`, specifying the `pool-id` and the `amount`. The contract records their position, updates the pool's total staked amount, and refreshes the pool's reward accounting.

### Unstaking Tokens

When users wish to withdraw their staked tokens, they call `unstake-tokens`. They can choose to unstake a partial or full amount. Upon unstaking, their accumulated rewards are calculated, the protocol fee is deducted, and the user receives both their unstaked principal and the net rewards. The contract also updates the pool's total staked amount and the user's position.

### Claiming Rewards

Users can claim only their pending rewards without unstaking their principal by calling `claim-rewards`. The contract calculates the pending rewards, applies the protocol fee, and updates the user's reward debt.

### Batch Claiming Rewards

The `batch-claim-rewards` function allows users to collect rewards from multiple pools simultaneously. It iterates through a provided list of `pool-id`s (up to 5) and executes a `claim-rewards` operation for each.

### Portfolio Summary

The `get-user-portfolio-summary` function offers a convenient way for users to review their overall yield farming activity on the platform. It aggregates data from the first five pools (u1-u5), providing a holistic view of their staked capital, total pending rewards, the number of active positions, and a basic "portfolio health" indicator. This function helps users quickly assess their diversification.

-----

## Errors

The contract uses specific error codes to indicate various issues:

  * `u100`: `ERR-OWNER-ONLY` - Only the contract owner can perform this action.
  * `u101`: `ERR-NOT-FOUND` - The specified pool or user position does not exist.
  * `u102`: `ERR-INVALID-AMOUNT` - The provided amount is invalid (e.g., zero, or less than minimum stake).
  * `u103`: `ERR-INSUFFICIENT-BALANCE` - The user is attempting to unstake more than they have staked.
  * `u104`: `ERR-POOL-INACTIVE` - The target pool is not active.
  * `u105`: `ERR-ALREADY-EXISTS` - This error is defined but not explicitly used in an `asserts!` in the current contract version.

-----

## Usage

To interact with this contract, you'll need a Stacks wallet and some STX tokens for transaction fees. You can interact directly with the deployed contract on the Stacks blockchain via a client library or through a block explorer.

Example interaction (pseudo-code):

```clarity
;; Deploy the contract first
;; (deploy .yield-aggregator)

;; Contract Owner: Create a new pool
(as-contract (contract-call? 'SP123...my-token-contract .create-pool 'SP456...reward-token-contract u1000 u5000000))

;; User: Stake tokens
(as-contract (contract-call? 'SP123...my-token-contract .stake-tokens u1 u10000000)) ;; Stake 10 tokens in pool 1

;; User: Check pending rewards
(contract-call? .yield-aggregator get-pending-rewards tx-sender u1)

;; User: Claim rewards
(as-contract (contract-call? 'SP123...my-token-contract .claim-rewards u1))

;; User: Check portfolio summary
(contract-call? .yield-aggregator get-user-portfolio-summary tx-sender)
```

-----

## Development & Testing

This contract is written in Clarity and can be developed and tested using the Clarity SDK and the Stacks CLI.

1.  **Clone the repository:** (If applicable)
    ```bash
    git clone [repository-url]
    cd yield-aggregator
    ```
2.  **Install Stacks CLI:**
    ```bash
    npm install -g @stacks/cli
    ```
3.  **Run tests:** (If test suite exists)
    ```bash
    # Assuming a clarity test setup
    npx clarity-cli test
    ```
    Or, you can use the Clarity REPL for interactive testing.

-----

## Contributing

Contributions are welcome\! If you find any issues or have suggestions for improvements, please open an issue or submit a pull request on the GitHub repository.

When contributing, please ensure:

  * Your code adheres to Clarity best practices.
  * You include appropriate tests for new features or bug fixes.
  * Your commits are clear and descriptive.

-----

## License

This project is licensed under the MIT License. See the LICENSE file for details.
