;; Chain Registry Contract
;; Manages supported blockchains and their configurations

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-OWNER-ONLY (err u100))
(define-constant ERR-CHAIN-EXISTS (err u101))
(define-constant ERR-CHAIN-NOT-FOUND (err u102))
(define-constant ERR-INVALID-CHAIN-ID (err u103))
(define-constant ERR-INVALID-ADDRESS (err u104))
(define-constant ERR-CHAIN-INACTIVE (err u105))

;; Data Variables
(define-data-var contract-owner principal CONTRACT-OWNER)

;; Data Maps
(define-map supported-chains 
  uint 
  {
    name: (string-ascii 20),
    bridge-address: (string-ascii 42),
    gas-token: principal,
    active: bool,
    block-time: uint,
    confirmation-blocks: uint
  }
)

(define-map chain-metrics
  uint
  {
    total-bridges: uint,
    total-volume: uint,
    last-activity: uint
  }
)

;; Read-only functions

(define-read-only (get-contract-owner)
  (var-get contract-owner)
)

(define-read-only (get-supported-chain (chain-id uint))
  (map-get? supported-chains chain-id)
)

(define-read-only (get-chain-metrics (chain-id uint))
  (map-get? chain-metrics chain-id)
)

(define-read-only (is-chain-active (chain-id uint))
  (match (map-get? supported-chains chain-id)
    chain-info (get active chain-info)
    false
  )
)

(define-read-only (get-bridge-address (chain-id uint))
  (match (map-get? supported-chains chain-id)
    chain-info 
      (if (get active chain-info)
        (some (get bridge-address chain-info))
        none
      )
    none
  )
)

(define-read-only (get-gas-token (chain-id uint))
  (match (map-get? supported-chains chain-id)
    chain-info 
      (if (get active chain-info)
        (some (get gas-token chain-info))
        none
      )
    none
  )
)

;; Private functions

(define-private (is-owner)
  (is-eq tx-sender (var-get contract-owner))
)

(define-private (validate-chain-id (chain-id uint))
  (> chain-id u0)
)

(define-private (validate-bridge-address (address (string-ascii 42)))
  (> (len address) u0)
)

;; Public functions

(define-public (add-supported-chain 
  (chain-id uint)
  (chain-info {
    name: (string-ascii 20), 
    bridge-address: (string-ascii 42),
    gas-token: principal,
    block-time: uint,
    confirmation-blocks: uint
  })
)
  (begin
    ;; Check if caller is owner
    (asserts! (is-owner) ERR-OWNER-ONLY)
    
    ;; Validate chain ID
    (asserts! (validate-chain-id chain-id) ERR-INVALID-CHAIN-ID)
    
    ;; Validate bridge address
    (asserts! (validate-bridge-address (get bridge-address chain-info)) ERR-INVALID-ADDRESS)
    
    ;; Check if chain already exists
    (asserts! (is-none (map-get? supported-chains chain-id)) ERR-CHAIN-EXISTS)
    
    ;; Add the chain
    (map-set supported-chains chain-id {
      name: (get name chain-info),
      bridge-address: (get bridge-address chain-info),
      gas-token: (get gas-token chain-info),
      active: true,
      block-time: (get block-time chain-info),
      confirmation-blocks: (get confirmation-blocks chain-info)
    })
    
    ;; Initialize metrics
    (map-set chain-metrics chain-id {
      total-bridges: u0,
      total-volume: u0,
      last-activity: block-height
    })
    
    ;; Print event
    (print {
      event: "chain-added",
      chain-id: chain-id,
      name: (get name chain-info),
      bridge-address: (get bridge-address chain-info)
    })
    
    (ok chain-id)
  )
)

(define-public (update-chain-info
  (chain-id uint)
  (updates {
    name: (optional (string-ascii 20)),
    bridge-address: (optional (string-ascii 42)),
    gas-token: (optional principal),
    block-time: (optional uint),
    confirmation-blocks: (optional uint)
  })
)
  (begin
    ;; Check if caller is owner
    (asserts! (is-owner) ERR-OWNER-ONLY)
    
    ;; Check if chain exists
    (match (map-get? supported-chains chain-id)
      current-info
        (begin
          (map-set supported-chains chain-id {
            name: (default-to (get name current-info) (get name updates)),
            bridge-address: (default-to (get bridge-address current-info) (get bridge-address updates)),
            gas-token: (default-to (get gas-token current-info) (get gas-token updates)),
            active: (get active current-info),
            block-time: (default-to (get block-time current-info) (get block-time updates)),
            confirmation-blocks: (default-to (get confirmation-blocks current-info) (get confirmation-blocks updates))
          })
          
          ;; Print event
          (print {
            event: "chain-updated",
            chain-id: chain-id
          })
          
          (ok true)
        )
      ERR-CHAIN-NOT-FOUND
    )
  )
)

(define-public (toggle-chain-status (chain-id uint))
  (begin
    ;; Check if caller is owner
    (asserts! (is-owner) ERR-OWNER-ONLY)
    
    ;; Check if chain exists and toggle status
    (match (map-get? supported-chains chain-id)
      current-info
        (begin
          (map-set supported-chains chain-id 
            (merge current-info {active: (not (get active current-info))})
          )
          
          ;; Print event
          (print {
            event: "chain-status-toggled",
            chain-id: chain-id,
            new-status: (not (get active current-info))
          })
          
          (ok (not (get active current-info)))
        )
      ERR-CHAIN-NOT-FOUND
    )
  )
)

(define-public (remove-supported-chain (chain-id uint))
  (begin
    ;; Check if caller is owner
    (asserts! (is-owner) ERR-OWNER-ONLY)
    
    ;; Check if chain exists
    (asserts! (is-some (map-get? supported-chains chain-id)) ERR-CHAIN-NOT-FOUND)
    
    ;; Remove the chain
    (map-delete supported-chains chain-id)
    (map-delete chain-metrics chain-id)
    
    ;; Print event
    (print {
      event: "chain-removed",
      chain-id: chain-id
    })
    
    (ok true)
  )
)

(define-public (update-chain-metrics
  (chain-id uint)
  (bridge-count-increment uint)
  (volume-increment uint)
)
  (begin
    ;; Check if chain exists and is active
    (asserts! (is-chain-active chain-id) ERR-CHAIN-INACTIVE)
    
    ;; Update metrics
    (match (map-get? chain-metrics chain-id)
      current-metrics
        (begin
          (map-set chain-metrics chain-id {
            total-bridges: (+ (get total-bridges current-metrics) bridge-count-increment),
            total-volume: (+ (get total-volume current-metrics) volume-increment),
            last-activity: block-height
          })
          (ok true)
        )
      ERR-CHAIN-NOT-FOUND
    )
  )
)

(define-public (transfer-ownership (new-owner principal))
  (begin
    ;; Check if caller is current owner
    (asserts! (is-owner) ERR-OWNER-ONLY)
    
    ;; Transfer ownership
    (var-set contract-owner new-owner)
    
    ;; Print event
    (print {
      event: "ownership-transferred",
      old-owner: tx-sender,
      new-owner: new-owner
    })
    
    (ok true)
  )
)

;; Batch operations

(define-public (add-multiple-chains 
  (chains (list 10 {
    chain-id: uint,
    name: (string-ascii 20),
    bridge-address: (string-ascii 42),
    gas-token: principal,
    block-time: uint,
    confirmation-blocks: uint
  }))
)
  (begin
    ;; Check if caller is owner
    (asserts! (is-owner) ERR-OWNER-ONLY)
    
    ;; Add each chain
    (fold add-chain-from-list chains (ok (list)))
  )
)

(define-private (add-chain-from-list 
  (chain-data {
    chain-id: uint,
    name: (string-ascii 20),
    bridge-address: (string-ascii 42),
    gas-token: principal,
    block-time: uint,
    confirmation-blocks: uint
  })
  (acc (response (list 10 uint) uint))
)
  (match acc
    success-list
      (match (add-supported-chain 
        (get chain-id chain-data)
        {
          name: (get name chain-data),
          bridge-address: (get bridge-address chain-data),
          gas-token: (get gas-token chain-data),
          block-time: (get block-time chain-data),
          confirmation-blocks: (get confirmation-blocks chain-data)
        }
      )
        chain-id (ok (unwrap-panic (as-max-len? (append success-list chain-id) u10)))
        error-code (err error-code)
      )
    error-code (err error-code)
  )
)
