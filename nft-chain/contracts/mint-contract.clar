;; Digital Asset Marketplace - Stage 1
;; Basic implementation with core asset publishing and purchasing

;; Define constants
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-ASSET-ALREADY-LICENSED (err u101))
(define-constant ERR-INSUFFICIENT-FUNDS (err u102))
(define-constant ERR-ASSET-UNAVAILABLE (err u103))
(define-constant ERR-FILESIZE-INVALID (err u104))
(define-constant ERR-LICENSE-PERIOD-INVALID (err u105))
(define-constant ERR-ASSET-ID-INVALID (err u106))
(define-constant ERR-INVALID-AMOUNT (err u107))
(define-constant MAX-CREDIT-AMOUNT u1000000000)

;; Define data maps
(define-map asset-registry 
  { asset-id: uint }
  {
    creator: principal,
    licensee: (optional principal),
    filesize: uint,
    license-period: uint,
    purchase-block: (optional uint),
    storage-location: (string-ascii 30),
    listing-status: (string-ascii 20)
  }
)

(define-map credit-balances principal uint)

;; Define data variable for asset counter
(define-data-var asset-counter uint u0)

;; Define functions
(define-public (publish-asset (filesize uint) (license-period uint) 
                             (storage-location (string-ascii 30)))
  (let ((asset-id (+ (var-get asset-counter) u1)))
    ;; Validate input parameters
    (asserts! (> filesize u0) ERR-FILESIZE-INVALID)
    (asserts! (and (> license-period u0) (<= license-period u10000)) ERR-LICENSE-PERIOD-INVALID)
    
    (map-set asset-registry 
      { asset-id: asset-id }
      {
        creator: tx-sender,
        licensee: none,
        filesize: filesize,
        license-period: license-period,
        purchase-block: none,
        storage-location: storage-location,
        listing-status: "AVAILABLE"
      }
    )
    
    (var-set asset-counter asset-id)
    (ok asset-id)
  )
)

(define-public (purchase-license (asset-id uint))
  (let (
    (asset-data (unwrap! (map-get? asset-registry { asset-id: asset-id }) ERR-ASSET-UNAVAILABLE))
    (buyer-balance (default-to u0 (map-get? credit-balances tx-sender)))
  )
    ;; Validate asset ID and status
    (asserts! (<= asset-id (var-get asset-counter)) ERR-ASSET-ID-INVALID)
    (asserts! (is-none (get licensee asset-data)) ERR-ASSET-ALREADY-LICENSED)
    (asserts! (is-eq (get listing-status asset-data) "AVAILABLE") ERR-ASSET-UNAVAILABLE)
    (asserts! (>= buyer-balance (get filesize asset-data)) ERR-INSUFFICIENT-FUNDS)
    
    (map-set asset-registry { asset-id: asset-id }
      (merge asset-data { 
        licensee: (some tx-sender),
        purchase-block: (some block-height),
        listing-status: "LICENSED"
      })
    )
    (map-set credit-balances tx-sender (- buyer-balance (get filesize asset-data)))
    (map-set credit-balances (get creator asset-data) (+ (default-to u0 (map-get? credit-balances (get creator asset-data))) (get filesize asset-data)))
    (ok true)
  )
)

(define-public (add-credits (amount uint))
  (let (
    (current-balance (default-to u0 (map-get? credit-balances tx-sender)))
  )
    ;; Validate amount to prevent integer overflow
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (<= amount MAX-CREDIT-AMOUNT) ERR-INVALID-AMOUNT)
    (asserts! (<= (+ current-balance amount) MAX-CREDIT-AMOUNT) ERR-INVALID-AMOUNT)
    
    (map-set credit-balances tx-sender (+ current-balance amount))
    (ok true)
  )
)

;; Read-only functions
(define-read-only (get-asset-details (asset-id uint))
  (map-get? asset-registry { asset-id: asset-id })
)

(define-read-only (check-credit-balance (user principal))
  (default-to u0 (map-get? credit-balances user))
)