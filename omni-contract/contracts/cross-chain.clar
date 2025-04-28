;; OmniSwap Invoice Tokenization Contract
;; Enables conversion of invoices into tradable digital assets with cryptographic validation

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-issuer (err u101))
(define-constant err-not-verifier (err u102))
(define-constant err-invalid-params (err u103))
(define-constant err-invoice-exists (err u104))
(define-constant err-invoice-not-found (err u105))
(define-constant err-not-verified (err u106))
(define-constant err-already-verified (err u107))
(define-constant err-already-tokenized (err u108))
(define-constant err-insufficient-shares (err u109))
(define-constant err-invalid-signature (err u110))

;; Data structures

;; Invoice data
(define-map invoices
  { invoice-id: uint }
  {
    invoice-number: (string-ascii 50),
    issuer: principal,
    payer: principal,
    amount: uint,
    due-date: uint,
    fractions: uint,
    verified: bool,
    document-hash: (buff 32)
  }
)

;; Map invoice numbers to IDs
(define-map invoice-number-to-id
  { invoice-number: (string-ascii 50) }
  { invoice-id: uint }
)

;; Track investor shares for each invoice
(define-map investor-shares
  { invoice-id: uint, investor: principal }
  { shares: uint }
)

;; Track the total supply of tokenized fractions for each invoice
(define-map invoice-token-supply
  { invoice-id: uint }
  { total-supply: uint }
)

;; Role-based access control
(define-map roles
  { role: (string-ascii 20), principal: principal }
  { has-role: bool }
)

;; Invoice ID counter
(define-data-var next-invoice-id uint u1)

;; Administrative functions

;; Grant a role to a principal
(define-public (grant-role (role (string-ascii 20)) (user principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map-set roles { role: role, principal: user } { has-role: true }))
  )
)

;; Revoke a role from a principal
(define-public (revoke-role (role (string-ascii 20)) (user principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map-set roles { role: role, principal: user } { has-role: false }))
  )
)

;; Check if a principal has a specific role
(define-read-only (has-role (role (string-ascii 20)) (user principal))
  (default-to false (get has-role (map-get? roles { role: role, principal: user })))
)

;; Core contract functions

;; Create a new invoice record
(define-public (create-invoice 
  (invoice-number (string-ascii 50))
  (payer principal)
  (amount uint)
  (due-date uint)
  (document-hash (buff 32))
)
  (let (
    (invoice-id (var-get next-invoice-id))
    (existing-id (map-get? invoice-number-to-id { invoice-number: invoice-number }))
  )
    ;; Verify the caller has issuer role
    (asserts! (has-role "issuer" tx-sender) err-not-issuer)
    ;; Check if invoice number already exists
    (asserts! (is-none existing-id) err-invoice-exists)
    ;; Validate parameters
    (asserts! (> amount u0) err-invalid-params)
    (asserts! (> due-date (unwrap-panic (get-block-info? time u0))) err-invalid-params)
    
    ;; Store the invoice data
    (map-set invoices 
      { invoice-id: invoice-id }
      {
        invoice-number: invoice-number,
        issuer: tx-sender,
        payer: payer,
        amount: amount,
        due-date: due-date,
        fractions: u0,
        verified: false,
        document-hash: document-hash
      }
    )
    
    ;; Map invoice number to id for lookup
    (map-set invoice-number-to-id
      { invoice-number: invoice-number }
      { invoice-id: invoice-id }
    )
    
    ;; Increment the invoice ID counter
    (var-set next-invoice-id (+ invoice-id u1))
    
    ;; Return the new invoice ID
    (ok invoice-id)
  )
)

;; Verify an invoice using a signature
(define-public (verify-invoice (invoice-id uint) (signature (buff 65)))
  (let (
    (invoice-data (map-get? invoices { invoice-id: invoice-id }))
  )
    ;; Verify the caller has verifier role
    (asserts! (has-role "verifier" tx-sender) err-not-verifier)
    ;; Check if invoice exists
    (asserts! (is-some invoice-data) err-invoice-not-found)
    
    (let (
      (invoice (unwrap-panic invoice-data))
    )
      ;; Check if invoice is already verified
      (asserts! (not (get verified invoice)) err-already-verified)
      
      ;; Validate signature (simplified - in production would use proper signature validation)
      ;; This is a placeholder for actual cryptographic signature verification
      (asserts! (is-valid-signature invoice-id signature) err-invalid-signature)
      
      ;; Update invoice as verified
      (map-set invoices
        { invoice-id: invoice-id }
        (merge invoice { verified: true })
      )
      
      (ok true)
    )
  )
)

;; Tokenize an invoice into fungible fractions
(define-public (tokenize-invoice (invoice-id uint) (fractions uint))
  (let (
    (invoice-data (map-get? invoices { invoice-id: invoice-id }))
  )
    ;; Check if invoice exists
    (asserts! (is-some invoice-data) err-invoice-not-found)
    
    (let (
      (invoice (unwrap-panic invoice-data))
    )
      ;; Check if caller is the invoice issuer
      (asserts! (is-eq (get issuer invoice) tx-sender) err-not-issuer)
      ;; Check if invoice is verified
      (asserts! (get verified invoice) err-not-verified)
      ;; Check if invoice is already tokenized
      (asserts! (is-eq (get fractions invoice) u0) err-already-tokenized)
      ;; Validate fractions
      (asserts! (> fractions u0) err-invalid-params)
      
      ;; Update invoice with fractions
      (map-set invoices
        { invoice-id: invoice-id }
        (merge invoice { fractions: fractions })
      )
      
      ;; Assign all fractions to the issuer initially
      (map-set investor-shares
        { invoice-id: invoice-id, investor: tx-sender }
        { shares: fractions }
      )
      
      ;; Set the total supply
      (map-set invoice-token-supply
        { invoice-id: invoice-id }
        { total-supply: fractions }
      )
      
      (ok true)
    )
  )
)

;; Transfer invoice fractions to another address
(define-public (transfer-shares (invoice-id uint) (recipient principal) (amount uint))
  (let (
    (sender-shares-data (map-get? investor-shares { invoice-id: invoice-id, investor: tx-sender }))
  )
    ;; Check if sender has any shares
    (asserts! (is-some sender-shares-data) err-insufficient-shares)
    
    (let (
      (sender-shares (get shares (unwrap-panic sender-shares-data)))
      (recipient-shares-data (map-get? investor-shares { invoice-id: invoice-id, investor: recipient }))
      (recipient-current-shares (if (is-some recipient-shares-data)
                                   (get shares (unwrap-panic recipient-shares-data))
                                   u0))
    )
      ;; Check if sender has enough shares
      (asserts! (>= sender-shares amount) err-insufficient-shares)
      
      ;; Update sender shares
      (map-set investor-shares
        { invoice-id: invoice-id, investor: tx-sender }
        { shares: (- sender-shares amount) }
      )
      
      ;; Update recipient shares
      (map-set investor-shares
        { invoice-id: invoice-id, investor: recipient }
        { shares: (+ recipient-current-shares amount) }
      )
      
      (ok true)
    )
  )
)

;; Read-only functions

;; Get invoice details
(define-read-only (get-invoice (invoice-id uint))
  (map-get? invoices { invoice-id: invoice-id })
)

;; Get invoice ID from invoice number
(define-read-only (get-invoice-id (invoice-number (string-ascii 50)))
  (map-get? invoice-number-to-id { invoice-number: invoice-number })
)

;; Get investor shares for an invoice
(define-read-only (get-investor-shares (invoice-id uint) (investor principal))
  (default-to { shares: u0 } 
    (map-get? investor-shares { invoice-id: invoice-id, investor: investor })
  )
)

;; Get total supply of fractions for an invoice
(define-read-only (get-total-supply (invoice-id uint))
  (default-to { total-supply: u0 }
    (map-get? invoice-token-supply { invoice-id: invoice-id })
  )
)

;; Verify if a document hash matches the stored invoice hash
(define-read-only (verify-document-hash (invoice-id uint) (hash (buff 32)))
  (let (
    (invoice-data (map-get? invoices { invoice-id: invoice-id }))
  )
    (if (is-some invoice-data)
      (is-eq (get document-hash (unwrap-panic invoice-data)) hash)
      false
    )
  )
)

;; Helper functions

;; Simplified signature validation (placeholder)
;; In a real implementation, this would use proper cryptographic verification
(define-private (is-valid-signature (invoice-id uint) (signature (buff 65)))
  (let (
    (invoice-data (map-get? invoices { invoice-id: invoice-id }))
  )
    (if (is-some invoice-data)
      (let (
        (invoice (unwrap-panic invoice-data))
        ;; This is where you would implement actual signature verification
        ;; For now, we'll just return true as a placeholder
      )
        true
      )
      false
    )
  )
)