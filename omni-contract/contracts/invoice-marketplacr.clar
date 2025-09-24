;; Invoice Marketplace Contract
;; Handles listing, buying, and selling of tokenized invoices

(define-trait nft-trait
    (
        ;; Last token ID, limited to uint range
        (get-last-token-id () (response uint uint))

        ;; URI for metadata associated with the token
        (get-token-uri (uint) (response (optional (string-ascii 256)) uint))

        ;; Owner of a given token identifier
        (get-owner (uint) (response (optional principal) uint))

        ;; Transfer from the sender to a new principal
        (transfer (uint principal principal) (response bool uint))
    )
)

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-OWNER-ONLY (err u200))
(define-constant ERR-NOT-FOUND (err u201))
(define-constant ERR-ALREADY-LISTED (err u202))
(define-constant ERR-NOT-LISTED (err u203))
(define-constant ERR-INSUFFICIENT-FUNDS (err u204))
(define-constant ERR-INVALID-PRICE (err u205))
(define-constant ERR-EXPIRED-LISTING (err u206))
(define-constant ERR-UNAUTHORIZED (err u207))
(define-constant ERR-INVALID-TERMS (err u208))

;; Data Variables
(define-data-var platform-fee-rate uint u250) ;; 2.5% in basis points
(define-data-var next-listing-id uint u1)

;; Listing Structure
(define-map listings uint {
    token-id: uint,
    seller: principal,
    price: uint,
    listing-expiry: uint,
    min-purchase-amount: uint,
    max-purchase-amount: uint,
    payment-terms: (string-utf8 256),
    status: (string-ascii 20), ;; "active", "sold", "cancelled", "expired"
    created-at: uint
})

;; Purchase Agreements
(define-map purchase-agreements uint {
    listing-id: uint,
    buyer: principal,
    seller: principal,
    token-id: uint,
    purchase-amount: uint,
    agreed-price: uint,
    agreement-date: uint,
    settlement-date: uint,
    status: (string-ascii 20), ;; "pending", "completed", "defaulted"
    terms: (string-utf8 512)
})

;; Mapping for quick lookups
(define-map token-listings uint uint) ;; token-id -> listing-id
(define-map user-listings principal (list 100 uint))
(define-map active-listings (list 200 uint) bool)

(define-data-var next-agreement-id uint u1)

;; Listing Functions
(define-public (list-invoice 
    (nft-contract <nft-trait>)
    (token-id uint)
    (price uint)
    (listing-expiry uint)
    (min-purchase-amount uint)
    (max-purchase-amount uint)
    (payment-terms (string-utf8 256))
)
    (let 
        (
            (listing-id (var-get next-listing-id))
            (token-owner (unwrap! (contract-call? nft-contract get-owner token-id) ERR-NOT-FOUND))
        )
        ;; Verify ownership
        (asserts! (is-eq (some tx-sender) token-owner) ERR-UNAUTHORIZED)
        (asserts! (is-none (map-get? token-listings token-id)) ERR-ALREADY-LISTED)
        (asserts! (> price u0) ERR-INVALID-PRICE)
        (asserts! (> listing-expiry block-height) ERR-EXPIRED-LISTING)
        (asserts! (<= min-purchase-amount max-purchase-amount) ERR-INVALID-TERMS)
        
        ;; Create listing
        (map-set listings listing-id {
            token-id: token-id,
            seller: tx-sender,
            price: price,
            listing-expiry: listing-expiry,
            min-purchase-amount: min-purchase-amount,
            max-purchase-amount: max-purchase-amount,
            payment-terms: payment-terms,
            status: "active",
            created-at: block-height
        })
        
        (map-set token-listings token-id listing-id)
        (var-set next-listing-id (+ listing-id u1))
        
        (print {
            action: "list-invoice",
            listing-id: listing-id,
            token-id: token-id,
            seller: tx-sender,
            price: price
        })
        
        (ok listing-id)
    )
)

(define-public (cancel-listing (listing-id uint))
    (let 
        (
            (listing (unwrap! (map-get? listings listing-id) ERR-NOT-FOUND))
        )
        (asserts! (is-eq tx-sender (get seller listing)) ERR-UNAUTHORIZED)
        (asserts! (is-eq (get status listing) "active") ERR-NOT-LISTED)
        
        (map-set listings listing-id (merge listing {status: "cancelled"}))
        (map-delete token-listings (get token-id listing))
        
        (print {action: "cancel-listing", listing-id: listing-id})
        (ok true)
    )
)

;; Purchase Functions
(define-public (create-purchase-agreement
    (listing-id uint)
    (purchase-amount uint)
    (settlement-date uint)
    (terms (string-utf8 512))
)
    (let 
        (
            (listing (unwrap! (map-get? listings listing-id) ERR-NOT-FOUND))
            (agreement-id (var-get next-agreement-id))
        )
        (asserts! (is-eq (get status listing) "active") ERR-NOT-LISTED)
        (asserts! (< block-height (get listing-expiry listing)) ERR-EXPIRED-LISTING)
        (asserts! (>= purchase-amount (get min-purchase-amount listing)) ERR-INVALID-TERMS)
        (asserts! (<= purchase-amount (get max-purchase-amount listing)) ERR-INVALID-TERMS)
        (asserts! (> settlement-date block-height) ERR-INVALID-TERMS)
        
        (map-set purchase-agreements agreement-id {
            listing-id: listing-id,
            buyer: tx-sender,
            seller: (get seller listing),
            token-id: (get token-id listing),
            purchase-amount: purchase-amount,
            agreed-price: (get price listing),
            agreement-date: block-height,
            settlement-date: settlement-date,
            status: "pending",
            terms: terms
        })
        
        (var-set next-agreement-id (+ agreement-id u1))
        
        (print {
            action: "create-purchase-agreement",
            agreement-id: agreement-id,
            listing-id: listing-id,
            buyer: tx-sender,
            purchase-amount: purchase-amount
        })
        
        (ok agreement-id)
    )
)

(define-public (execute-purchase 
    (nft-contract <nft-trait>)
    (agreement-id uint)
)
    (let 
        (
            (agreement (unwrap! (map-get? purchase-agreements agreement-id) ERR-NOT-FOUND))
            (listing (unwrap! (map-get? listings (get listing-id agreement)) ERR-NOT-FOUND))
            (platform-fee (/ (* (get agreed-price agreement) (var-get platform-fee-rate)) u10000))
            (seller-amount (- (get agreed-price agreement) platform-fee))
        )
        (asserts! (is-eq (get status agreement) "pending") ERR-INVALID-TERMS)
        (asserts! (is-eq tx-sender (get buyer agreement)) ERR-UNAUTHORIZED)
        
        ;; Transfer payment to seller (minus platform fee)
        (try! (stx-transfer? seller-amount tx-sender (get seller agreement)))
        
        ;; Transfer platform fee to contract owner
        (try! (stx-transfer? platform-fee tx-sender CONTRACT-OWNER))
        
        ;; Transfer NFT to buyer
        (try! (contract-call? nft-contract transfer 
            (get token-id agreement) 
            (get seller agreement) 
            (get buyer agreement)
        ))
        
        ;; Update agreement status
        (map-set purchase-agreements agreement-id 
            (merge agreement {status: "completed"}))
        
        ;; Update listing status
        (map-set listings (get listing-id agreement) 
            (merge listing {status: "sold"}))
        
        ;; Remove from token listings
        (map-delete token-listings (get token-id agreement))
        
        (print {
            action: "execute-purchase",
            agreement-id: agreement-id,
            buyer: (get buyer agreement),
            seller: (get seller agreement),
            price: (get agreed-price agreement),
            platform-fee: platform-fee
        })
        
        (ok true)
    )
)
