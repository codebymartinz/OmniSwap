;; Dynamic Discounting Engine Smart Contract
;; Handles early payment discounts with time-based curves and automatic adjustments

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVOICE-NOT-FOUND (err u101))
(define-constant ERR-INVALID-DISCOUNT (err u102))
(define-constant ERR-PAYMENT-ALREADY-MADE (err u103))
(define-constant ERR-DISCOUNT-EXPIRED (err u104))
(define-constant ERR-INSUFFICIENT-FUNDS (err u105))
(define-constant ERR-INVALID-PROPOSAL (err u106))
(define-constant ERR-PROPOSAL-NOT-FOUND (err u107))

;; Contract owner
(define-constant CONTRACT-OWNER tx-sender)

;; Data structures
(define-map invoices
  { invoice-id: uint }
  {
    supplier: principal,
    buyer: principal,
    amount: uint,
    due-date: uint,
    created-at: uint,
    paid: bool,
    payment-date: (optional uint),
    discount-applied: uint
  }
)

(define-map discount-curves
  { curve-id: uint }
  {
    name: (string-ascii 50),
    base-rate: uint,  ;; Base discount rate (basis points)
    max-rate: uint,   ;; Maximum discount rate (basis points)
    time-factor: uint, ;; Time sensitivity factor
    active: bool
  }
)

(define-map discount-proposals
  { proposal-id: uint }
  {
    invoice-id: uint,
    proposer: principal,
    discount-rate: uint,
    valid-until: uint,
    accepted: bool,
    created-at: uint
  }
)

;; Counters
(define-data-var next-invoice-id uint u1)
(define-data-var next-curve-id uint u1)
(define-data-var next-proposal-id uint u1)

;; Default discount curve parameters
(define-data-var default-curve-id uint u0)

;; Helper functions

;; Calculate days between two block heights (assuming ~10 min blocks)
(define-private (blocks-to-days (blocks uint))
  (/ blocks u144) ;; 144 blocks per day (10 min blocks)
)



;; Calculate discount amount
(define-private (calculate-discount-amount (amount uint) (discount-rate uint))
  (/ (* amount discount-rate) u10000) ;; discount-rate in basis points
)

;; Public functions

;; Initialize default discount curve
(define-public (initialize-default-curve)
  (let
    (
      (curve-id (var-get next-curve-id))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (map-set discount-curves
      { curve-id: curve-id }
      {
        name: "Default Curve",
        base-rate: u50,    ;; 0.5% base rate
        max-rate: u500,    ;; 5% maximum rate
        time-factor: u10,  ;; Time sensitivity
        active: true
      }
    )
    (var-set next-curve-id (+ curve-id u1))
    (var-set default-curve-id curve-id)
    (ok curve-id)
  )
)

;; Create a new invoice
(define-public (create-invoice (supplier principal) (buyer principal) (amount uint) (due-date uint))
  (let
    (
      (invoice-id (var-get next-invoice-id))
    )
    (asserts! (or (is-eq tx-sender supplier) (is-eq tx-sender buyer)) ERR-NOT-AUTHORIZED)
    (asserts! (> amount u0) ERR-INVALID-DISCOUNT)
    (asserts! (> due-date block-height) ERR-INVALID-DISCOUNT)
    
    (map-set invoices
      { invoice-id: invoice-id }
      {
        supplier: supplier,
        buyer: buyer,
        amount: amount,
        due-date: due-date,
        created-at: block-height,
        paid: false,
        payment-date: none,
        discount-applied: u0
      }
    )
    (var-set next-invoice-id (+ invoice-id u1))
    (ok invoice-id)
  )
)

;; Create discount curve
(define-public (create-discount-curve (name (string-ascii 50)) (base-rate uint) (max-rate uint) (time-factor uint))
  (let
    (
      (curve-id (var-get next-curve-id))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (<= base-rate max-rate) ERR-INVALID-DISCOUNT)
    (asserts! (<= max-rate u1000) ERR-INVALID-DISCOUNT) ;; Max 10%
    
    (map-set discount-curves
      { curve-id: curve-id }
      {
        name: name,
        base-rate: base-rate,
        max-rate: max-rate,
        time-factor: time-factor,
        active: true
      }
    )
    (var-set next-curve-id (+ curve-id u1))
    (ok curve-id)
  )
)

;; Calculate current discount for an invoice
;; (define-public (get-current-discount (invoice-id uint))
;;   (match (map-get? invoices { invoice-id: invoice-id })
;;     invoice-data
;;     (if (get paid invoice-data)
;;       (ok u0)
;;       (let
;;         (
;;           (due-date (get due-date invoice-data))
;;           (days-early (if (< block-height due-date)
;;                        (blocks-to-days (- due-date block-height))
;;                        u0))
;;           (discount-rate (calculate-discount-rate (var-get default-curve-id) days-early))
;;           (discount-amount (calculate-discount-amount (get amount invoice-data) discount-rate))
;;         )
;;         (ok { discount-rate: discount-rate, discount-amount: discount-amount, days-early: days-early })
;;       )
;;     )
;;     ERR-INVOICE-NOT-FOUND
;;   )
;; )

;; Buyer-initiated discount proposal
(define-public (propose-buyer-discount (invoice-id uint) (discount-rate uint) (valid-hours uint))
  (let
    (
      (proposal-id (var-get next-proposal-id))
      (valid-until (+ block-height (* valid-hours u6))) ;; 6 blocks per hour
    )
    (match (map-get? invoices { invoice-id: invoice-id })
      invoice-data
      (begin
        (asserts! (is-eq tx-sender (get buyer invoice-data)) ERR-NOT-AUTHORIZED)
        (asserts! (not (get paid invoice-data)) ERR-PAYMENT-ALREADY-MADE)
        (asserts! (<= discount-rate u1000) ERR-INVALID-PROPOSAL) ;; Max 10%
        
        (map-set discount-proposals
          { proposal-id: proposal-id }
          {
            invoice-id: invoice-id,
            proposer: tx-sender,
            discount-rate: discount-rate,
            valid-until: valid-until,
            accepted: false,
            created-at: block-height
          }
        )
        (var-set next-proposal-id (+ proposal-id u1))
        (ok proposal-id)
      )
      ERR-INVOICE-NOT-FOUND
    )
  )
)

;; Supplier-initiated discount proposal
(define-public (propose-supplier-discount (invoice-id uint) (discount-rate uint) (valid-hours uint))
  (let
    (
      (proposal-id (var-get next-proposal-id))
      (valid-until (+ block-height (* valid-hours u6))) ;; 6 blocks per hour
    )
    (match (map-get? invoices { invoice-id: invoice-id })
      invoice-data
      (begin
        (asserts! (is-eq tx-sender (get supplier invoice-data)) ERR-NOT-AUTHORIZED)
        (asserts! (not (get paid invoice-data)) ERR-PAYMENT-ALREADY-MADE)
        (asserts! (<= discount-rate u1000) ERR-INVALID-PROPOSAL) ;; Max 10%
        
        (map-set discount-proposals
          { proposal-id: proposal-id }
          {
            invoice-id: invoice-id,
            proposer: tx-sender,
            discount-rate: discount-rate,
            valid-until: valid-until,
            accepted: false,
            created-at: block-height
          }
        )
        (var-set next-proposal-id (+ proposal-id u1))
        (ok proposal-id)
      )
      ERR-INVOICE-NOT-FOUND
    )
  )
)

;; Accept discount proposal
(define-public (accept-proposal (proposal-id uint))
  (match (map-get? discount-proposals { proposal-id: proposal-id })
    proposal-data
    (match (map-get? invoices { invoice-id: (get invoice-id proposal-data) })
      invoice-data
      (let
        (
          (is-buyer (is-eq tx-sender (get buyer invoice-data)))
          (is-supplier (is-eq tx-sender (get supplier invoice-data)))
          (proposer (get proposer proposal-data))
        )
        (asserts! (or is-buyer is-supplier) ERR-NOT-AUTHORIZED)
        (asserts! (not (is-eq tx-sender proposer)) ERR-NOT-AUTHORIZED)
        (asserts! (< block-height (get valid-until proposal-data)) ERR-DISCOUNT-EXPIRED)
        (asserts! (not (get paid invoice-data)) ERR-PAYMENT-ALREADY-MADE)
        
        (map-set discount-proposals
          { proposal-id: proposal-id }
          (merge proposal-data { accepted: true })
        )
        (ok true)
      )
      ERR-INVOICE-NOT-FOUND
    )
    ERR-PROPOSAL-NOT-FOUND
  )
)

;; Process payment with discount
;; (define-public (pay-with-discount (invoice-id uint) (proposal-id (optional uint)))
;;   (match (map-get? invoices { invoice-id: invoice-id })
;;     invoice-data
;;     (let
;;       (
;;         (discount-rate 
;;           (match proposal-id
;;             pid
;;             (match (map-get? discount-proposals { proposal-id: pid })
;;               proposal-data
;;               (if (and (get accepted proposal-data) 
;;                        (< block-height (get valid-until proposal-data)))
;;                 (get discount-rate proposal-data)
;;                 u0)
;;               u0)
;;             ;; Use algorithmic discount if no proposal
;;             (unwrap-panic (get discount-rate (unwrap-panic (get-current-discount invoice-id))))
;;           )
;;         )
;;         (discount-amount (calculate-discount-amount (get amount invoice-data) discount-rate))
;;         (payment-amount (- (get amount invoice-data) discount-amount))
;;       )
;;       (asserts! (is-eq tx-sender (get buyer invoice-data)) ERR-NOT-AUTHORIZED)
;;       (asserts! (not (get paid invoice-data)) ERR-PAYMENT-ALREADY-MADE)
      
;;       ;; Update invoice as paid
;;       (map-set invoices
;;         { invoice-id: invoice-id }
;;         (merge invoice-data {
;;           paid: true,
;;           payment-date: (some block-height),
;;           discount-applied: discount-amount
;;         })
;;       )
      
;;       (ok { payment-amount: payment-amount, discount-applied: discount-amount })
;;     )
;;     ERR-INVOICE-NOT-FOUND
;;   )
;; )

;; Read-only functions

;; Get invoice details
(define-read-only (get-invoice (invoice-id uint))
  (map-get? invoices { invoice-id: invoice-id })
)

;; Get discount curve details
(define-read-only (get-discount-curve (curve-id uint))
  (map-get? discount-curves { curve-id: curve-id })
)

;; Get proposal details
(define-read-only (get-proposal (proposal-id uint))
  (map-get? discount-proposals { proposal-id: proposal-id })
)

;; Get next IDs
(define-read-only (get-next-invoice-id)
  (var-get next-invoice-id)
)

(define-read-only (get-next-curve-id)
  (var-get next-curve-id)
)

(define-read-only (get-next-proposal-id)
  (var-get next-proposal-id)
)