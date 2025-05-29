;; Yield Farming Aggregator Contract 
;; A robust Clarity smart contract for decentralized yield farming aggregation on
;; the Stacks blockchain, enabling users to stake tokens across multiple pools and earn rewards.

;; constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-OWNER-ONLY (err u100))
(define-constant ERR-NOT-FOUND (err u101))
(define-constant ERR-INVALID-AMOUNT (err u102))
(define-constant ERR-INSUFFICIENT-BALANCE (err u103))
(define-constant ERR-POOL-INACTIVE (err u104))
(define-constant ERR-ALREADY-EXISTS (err u105))
(define-constant MIN-DEPOSIT u1000000) ;; 1 token minimum
(define-constant PRECISION u1000000) ;; 6 decimals precision

;; data maps and vars
(define-map pools
  { pool-id: uint }
  {
    token-contract: principal,
    reward-token: principal,
    total-staked: uint,
    reward-rate: uint, ;; rewards per block per token
    last-update-block: uint,
    accumulated-reward-per-token: uint,
    is-active: bool,
    min-stake: uint
  }
)

(define-map user-positions
  { user: principal, pool-id: uint }
  {
    amount: uint,
    reward-debt: uint,
    last-claim-block: uint,
    entry-block: uint
  }
)

(define-map user-pool-count
  { user: principal }
  { count: uint }
)

(define-data-var pool-counter uint u0)
(define-data-var total-pools uint u0)
(define-data-var protocol-fee-rate uint u250) ;; 2.5% in basis points
(define-data-var fee-collector principal CONTRACT-OWNER)

;; private functions
(define-private (is-contract-owner)
  (is-eq tx-sender CONTRACT-OWNER)
)

(define-private (calculate-pending-rewards (user principal) (pool-id uint))
  (let (
    (pool-data (unwrap! (map-get? pools { pool-id: pool-id }) u0))
    (user-pos (unwrap! (map-get? user-positions { user: user, pool-id: pool-id }) u0))
    (blocks-passed (- block-height (get last-update-block pool-data)))
    (new-rewards-per-token (if (> (get total-staked pool-data) u0)
      (+ (get accumulated-reward-per-token pool-data)
         (/ (* blocks-passed (get reward-rate pool-data) PRECISION) (get total-staked pool-data)))
      (get accumulated-reward-per-token pool-data)))
  )
    (/ (* (get amount user-pos) (- new-rewards-per-token (get reward-debt user-pos))) PRECISION)
  )
)

(define-private (update-pool-rewards (pool-id uint))
  (let (
    (pool-data (unwrap! (map-get? pools { pool-id: pool-id }) (err u0)))
    (blocks-passed (- block-height (get last-update-block pool-data)))
  )
    (if (> blocks-passed u0)
      (ok (map-set pools { pool-id: pool-id }
        (merge pool-data {
          last-update-block: block-height,
          accumulated-reward-per-token: (if (> (get total-staked pool-data) u0)
            (+ (get accumulated-reward-per-token pool-data)
               (/ (* blocks-passed (get reward-rate pool-data) PRECISION) (get total-staked pool-data)))
            (get accumulated-reward-per-token pool-data))
        })
      ))
      (ok true)
    )
  )
)

(define-private (calculate-protocol-fee (amount uint))
  (/ (* amount (var-get protocol-fee-rate)) u10000)
)

(define-private (get-user-pool-data (user principal) (pool-id uint))
  (let (
    (user-pos-opt (map-get? user-positions { user: user, pool-id: pool-id }))
    (pool-exists (is-some (map-get? pools { pool-id: pool-id })))
  )
    (if (and pool-exists (is-some user-pos-opt))
      (let (
        (user-pos (unwrap-panic user-pos-opt))
        (pending-rewards (calculate-pending-rewards user pool-id))
      )
        {
          staked: (get amount user-pos),
          rewards: pending-rewards,
          active: u1
        }
      )
      { staked: u0, rewards: u0, active: u0 }
    )
  )
)

(define-private (claim-single-pool-rewards (pool-id uint))
  (let (
    (user-pos-opt (map-get? user-positions { user: tx-sender, pool-id: pool-id }))
  )
    (if (is-some user-pos-opt)
      (match (claim-rewards pool-id)
        success (get rewards-claimed success)
        error u0
      )
      u0
    )
  )
)

(define-private (sum-claimed-rewards (reward-amount uint) (total uint))
  (+ total reward-amount)
)

;; public functions
(define-public (create-pool (token-contract principal) (reward-token principal) (reward-rate uint) (min-stake uint))
  (let (
    (new-pool-id (+ (var-get pool-counter) u1))
  )
    (asserts! (is-contract-owner) ERR-OWNER-ONLY)
    (asserts! (> reward-rate u0) ERR-INVALID-AMOUNT)
    (asserts! (>= min-stake MIN-DEPOSIT) ERR-INVALID-AMOUNT)
    
    (map-set pools { pool-id: new-pool-id }
      {
        token-contract: token-contract,
        reward-token: reward-token,
        total-staked: u0,
        reward-rate: reward-rate,
        last-update-block: block-height,
        accumulated-reward-per-token: u0,
        is-active: true,
        min-stake: min-stake
      }
    )
    
    (var-set pool-counter new-pool-id)
    (var-set total-pools (+ (var-get total-pools) u1))
    (ok new-pool-id)
  )
)

(define-public (stake-tokens (pool-id uint) (amount uint))
  (let (
    (pool-data (unwrap! (map-get? pools { pool-id: pool-id }) ERR-NOT-FOUND))
    (existing-position (map-get? user-positions { user: tx-sender, pool-id: pool-id }))
    (current-amount (default-to u0 (get amount existing-position)))
    (pending-rewards (if (is-some existing-position) 
                       (calculate-pending-rewards tx-sender pool-id) 
                       u0))
  )
    (asserts! (get is-active pool-data) ERR-POOL-INACTIVE)
    (asserts! (>= amount (get min-stake pool-data)) ERR-INVALID-AMOUNT)
    
    ;; Update pool rewards first
    (try! (update-pool-rewards pool-id))
    
    ;; Update user position
    (map-set user-positions { user: tx-sender, pool-id: pool-id }
      {
        amount: (+ current-amount amount),
        reward-debt: (get accumulated-reward-per-token pool-data),
        last-claim-block: block-height,
        entry-block: (default-to block-height (get entry-block existing-position))
      }
    )
    
    ;; Update pool total
    (map-set pools { pool-id: pool-id }
      (merge pool-data { total-staked: (+ (get total-staked pool-data) amount) })
    )
    
    ;; Update user pool count if new position
    (if (is-none existing-position)
      (let ((current-count (default-to u0 (get count (map-get? user-pool-count { user: tx-sender })))))
        (map-set user-pool-count { user: tx-sender } { count: (+ current-count u1) })
      )
      true
    )
    
    (ok { staked: amount, pending-rewards: pending-rewards })
  )
)

(define-public (unstake-tokens (pool-id uint) (amount uint))
  (let (
    (pool-data (unwrap! (map-get? pools { pool-id: pool-id }) ERR-NOT-FOUND))
    (user-pos (unwrap! (map-get? user-positions { user: tx-sender, pool-id: pool-id }) ERR-NOT-FOUND))
    (pending-rewards (calculate-pending-rewards tx-sender pool-id))
    (protocol-fee (calculate-protocol-fee pending-rewards))
    (user-rewards (- pending-rewards protocol-fee))
  )
    (asserts! (<= amount (get amount user-pos)) ERR-INSUFFICIENT-BALANCE)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    
    ;; Update pool rewards
    (try! (update-pool-rewards pool-id))
    
    ;; Update user position
    (if (is-eq amount (get amount user-pos))
      ;; Complete withdrawal
      (begin
        (map-delete user-positions { user: tx-sender, pool-id: pool-id })
        (let ((current-count (default-to u1 (get count (map-get? user-pool-count { user: tx-sender })))))
          (if (> current-count u1)
            (map-set user-pool-count { user: tx-sender } { count: (- current-count u1) })
            (map-delete user-pool-count { user: tx-sender })
          )
        )
      )
      ;; Partial withdrawal
      (map-set user-positions { user: tx-sender, pool-id: pool-id }
        (merge user-pos {
          amount: (- (get amount user-pos) amount),
          reward-debt: (get accumulated-reward-per-token pool-data),
          last-claim-block: block-height
        })
      )
    )
    
    ;; Update pool total
    (map-set pools { pool-id: pool-id }
      (merge pool-data { total-staked: (- (get total-staked pool-data) amount) })
    )
    
    (ok { 
      unstaked: amount, 
      rewards-claimed: user-rewards,
      protocol-fee: protocol-fee 
    })
  )
)

(define-public (claim-rewards (pool-id uint))
  (let (
    (pool-data (unwrap! (map-get? pools { pool-id: pool-id }) ERR-NOT-FOUND))
    (user-pos (unwrap! (map-get? user-positions { user: tx-sender, pool-id: pool-id }) ERR-NOT-FOUND))
    (pending-rewards (calculate-pending-rewards tx-sender pool-id))
    (protocol-fee (calculate-protocol-fee pending-rewards))
    (user-rewards (- pending-rewards protocol-fee))
  )
    (asserts! (> pending-rewards u0) ERR-INVALID-AMOUNT)
    
    ;; Update pool rewards
    (try! (update-pool-rewards pool-id))
    
    ;; Update user position
    (map-set user-positions { user: tx-sender, pool-id: pool-id }
      (merge user-pos {
        reward-debt: (get accumulated-reward-per-token pool-data),
        last-claim-block: block-height
      })
    )
    
    (ok { rewards-claimed: user-rewards, protocol-fee: protocol-fee })
  )
)

;; read-only functions
(define-read-only (get-pool-info (pool-id uint))
  (map-get? pools { pool-id: pool-id })
)

(define-read-only (get-user-position (user principal) (pool-id uint))
  (map-get? user-positions { user: user, pool-id: pool-id })
)

(define-read-only (get-pending-rewards (user principal) (pool-id uint))
  (ok (calculate-pending-rewards user pool-id))
)

(define-read-only (get-total-pools)
  (var-get total-pools)
)

(define-public (batch-claim-rewards (pool-ids (list 5 uint)))
  (let (
    (results (map claim-single-pool-rewards pool-ids))
    (total-claimed (fold sum-claimed-rewards results u0))
  )
    (ok {
      pools-processed: (len pool-ids),
      total-rewards-claimed: total-claimed,
      individual-results: results
    })
  )
)


