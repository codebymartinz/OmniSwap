;; Role-Based Access Control Smart Contract
;; This contract manages user roles and permissions

;; Error constants
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ROLE-NOT-FOUND (err u101))
(define-constant ERR-ROLE-ALREADY-EXISTS (err u102))
(define-constant ERR-INVALID-ROLE (err u103))
(define-constant ERR-CANNOT-REVOKE-OWN-ADMIN (err u104))

;; Role constants
(define-constant ADMIN "admin")
(define-constant OPERATOR "operator")
(define-constant USER "user")

;; Contract owner (deployer becomes the first admin)
(define-constant CONTRACT-OWNER tx-sender)

;; Data maps
;; Maps user principals to a list of their roles
(define-map user-roles principal (list 10 (string-ascii 20)))

;; Maps to track valid roles in the system
(define-map valid-roles (string-ascii 20) bool)

;; Initialize the contract with valid roles and set deployer as admin
(map-set valid-roles ADMIN true)
(map-set valid-roles OPERATOR true)
(map-set valid-roles USER true)
(map-set user-roles CONTRACT-OWNER (list ADMIN))

;; Private functions

;; Check if a role is valid
(define-private (is-valid-role (role (string-ascii 20)))
  (default-to false (map-get? valid-roles role))
)

;; Check if caller is admin
(define-private (is-admin (user principal))
  (has-role user ADMIN)
)

;; Remove a role from a user's role list
(define-private (remove-role-from-list (role-to-remove (string-ascii 20)) (roles (list 10 (string-ascii 20))))
  (filter is-not-target-role roles)
)

;; Helper function for filtering roles
(define-private (is-not-target-role (role (string-ascii 20)))
  (not (is-eq role (var-get target-role)))
)

;; Variable to store target role for filtering (used in remove-role-from-list)
(define-data-var target-role (string-ascii 20) "")

;; Public functions

;; Grant a role to a user (only admins can grant roles)
(define-public (grant-role (user principal) (role (string-ascii 20)))
  (begin
    ;; Check if caller is admin
    (asserts! (is-admin tx-sender) ERR-NOT-AUTHORIZED)
    
    ;; Check if role is valid
    (asserts! (is-valid-role role) ERR-INVALID-ROLE)
    
    ;; Check if user already has the role
    (asserts! (not (has-role user role)) ERR-ROLE-ALREADY-EXISTS)
    
    ;; Get current roles or empty list
    (let ((current-roles (default-to (list) (map-get? user-roles user))))
      ;; Add new role to the list
      (match (as-max-len? (append current-roles role) u10)
        new-roles (begin
          (map-set user-roles user new-roles)
          (ok true)
        )
        ;; If list is full, return error
        ERR-INVALID-ROLE
      )
    )
  )
)

;; Revoke a role from a user (only admins can revoke roles)
(define-public (revoke-role (user principal) (role (string-ascii 20)))
  (begin
    ;; Check if caller is admin
    (asserts! (is-admin tx-sender) ERR-NOT-AUTHORIZED)
    
    ;; Check if role is valid
    (asserts! (is-valid-role role) ERR-INVALID-ROLE)
    
    ;; Prevent admin from revoking their own admin role
    (asserts! (not (and (is-eq user tx-sender) (is-eq role ADMIN))) ERR-CANNOT-REVOKE-OWN-ADMIN)
    
    ;; Check if user has the role
    (asserts! (has-role user role) ERR-ROLE-NOT-FOUND)
    
    ;; Get current roles
    (let ((current-roles (default-to (list) (map-get? user-roles user))))
      ;; Set target role for filtering
      (var-set target-role role)
      ;; Remove the role from the list
      (let ((new-roles (remove-role-from-list role current-roles)))
        (map-set user-roles user new-roles)
        (ok true)
      )
    )
  )
)

;; Add a new valid role to the system (only admins)
(define-public (add-valid-role (role (string-ascii 20)))
  (begin
    ;; Check if caller is admin
    (asserts! (is-admin tx-sender) ERR-NOT-AUTHORIZED)
    
    ;; Check if role doesn't already exist
    (asserts! (not (is-valid-role role)) ERR-ROLE-ALREADY-EXISTS)
    
    ;; Add the role
    (map-set valid-roles role true)
    (ok true)
  )
)

;; Read-only functions

;; Check if a user has a specific role
(define-read-only (has-role (user principal) (role (string-ascii 20)))
  (match (map-get? user-roles user)
    user-role-list (is-some (index-of user-role-list role))
    false
  )
)

;; Get all roles for a user
(define-read-only (get-user-roles (user principal))
  (map-get? user-roles user)
)

;; Check if a role is valid in the system
(define-read-only (is-role-valid (role (string-ascii 20)))
  (is-valid-role role)
)

;; Get the contract owner
(define-read-only (get-contract-owner)
  CONTRACT-OWNER
)

;; Check if user has admin privileges
(define-read-only (is-user-admin (user principal))
  (has-role user ADMIN)
)

;; Check if user has operator privileges
(define-read-only (is-user-operator (user principal))
  (has-role user OPERATOR)
)

;; Utility function to check if user has any of multiple roles
(define-read-only (has-any-role (user principal) (roles (list 10 (string-ascii 20))))
  (> (len (filter check-user-role roles)) u0)
)

;; Helper function for has-any-role
(define-private (check-user-role (role (string-ascii 20)))
  (has-role tx-sender role)
)
