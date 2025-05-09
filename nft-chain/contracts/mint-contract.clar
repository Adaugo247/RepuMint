;; Digital Asset Marketplace - Stage 3
;; Complete implementation with creator reputation and consumer purchase history

;; Define constants
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-ASSET-ALREADY-LICENSED (err u101))
(define-constant ERR-INSUFFICIENT-FUNDS (err u102))
(define-constant ERR-ASSET-UNAVAILABLE (err u103))
(define-constant ERR-LICENSING-IN-PROGRESS (err u104))
(define-constant ERR-FILESIZE-INVALID (err u105))
(define-constant ERR-ROYALTY-RATE-INVALID (err u106))
(define-constant ERR-LICENSE-PERIOD-INVALID (err u107))
(define-constant ERR-ASSET-ID-INVALID (err u108))
(define-constant ERR-QUALITY-TIER-INVALID (err u109))
(define-constant ERR-ASSET-DELISTED (err u110))
(define-constant ERR-INVALID-AMOUNT (err u111))
(define-constant ERR-INVALID-LOCATION (err u112))
(define-constant ERR-INVALID-TITLE (err u113))
(define-constant MAX-CREDIT-AMOUNT u1000000000)

;; Define data maps
(define-map asset-registry 
  { asset-id: uint }
  {
    creator: principal,
    licensee: (optional principal),
    filesize: uint,
    royalty-rate: uint,
    license-period: uint,
    quality-tier: uint,
    purchase-block: (optional uint),
    storage-location: (string-ascii 30),
    asset-title: (string-ascii 20),
    listing-status: (string-ascii 20)
  }
)

(define-map credit-balances principal uint)

(define-map creator-reputation principal uint)

(define-map consumer-purchase-history
  principal
  (list 10 uint)
)

;; Define data variable for asset counter
(define-data-var asset-counter uint u0)

;; Define functions
(define-public (publish-asset (filesize uint) (royalty-rate uint) (license-period uint) 
                             (quality-tier uint) (storage-location (string-ascii 30)) 
                             (asset-title (string-ascii 20)))
  (let ((asset-id (+ (var-get asset-counter) u1)))
    ;; Validate input parameters
    (asserts! (> filesize u0) ERR-FILESIZE-INVALID)
    (asserts! (<= royalty-rate u50) ERR-ROYALTY-RATE-INVALID)
    (asserts! (and (> license-period u0) (<= license-period u10000)) ERR-LICENSE-PERIOD-INVALID)
    (asserts! (and (>= quality-tier u1) (<= quality-tier u5)) ERR-QUALITY-TIER-INVALID)
    ;; Validate location and title - ensure they're not empty
    (asserts! (> (len storage-location) u0) ERR-INVALID-LOCATION)
    (asserts! (> (len asset-title) u0) ERR-INVALID-TITLE)
    
    (map-set asset-registry 
      { asset-id: asset-id }
      {
        creator: tx-sender,
        licensee: none,
        filesize: filesize,
        royalty-rate: royalty-rate,
        license-period: license-period,
        quality-tier: quality-tier,
        purchase-block: none,
        storage-location: storage-location,
        asset-title: asset-title,
        listing-status: "AVAILABLE"
      }
    )
    
    ;; Update creator's asset publication history
    (let 
      (
        (current-log (default-to (list) (map-get? consumer-purchase-history tx-sender)))
        (updated-log (unwrap-panic (as-max-len? (concat (list asset-id) current-log) u10)))
      )
      ;; Keep track of last 10 assets
      (map-set consumer-purchase-history tx-sender updated-log)
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
    
    ;; Update consumer's purchase history
    (let 
      (
        (current-log (default-to (list) (map-get? consumer-purchase-history tx-sender)))
        (updated-log (unwrap-panic (as-max-len? (concat (list asset-id) current-log) u10)))
      )
      ;; Keep track of last 10 assets
      (map-set consumer-purchase-history tx-sender updated-log)
    )
    
    (ok true)
  )
)

(define-public (confirm-usage (asset-id uint))
  (let (
    (asset-data (unwrap! (map-get? asset-registry { asset-id: asset-id }) ERR-ASSET-UNAVAILABLE))
    (licensee-balance (default-to u0 (map-get? credit-balances tx-sender)))
    (base-fee (get filesize asset-data))
    (royalty-fee (/ (* (get filesize asset-data) (get royalty-rate asset-data)) u100))
    (quality-fee (/ (* base-fee (get quality-tier asset-data)) u100))
    (total-fee (+ base-fee royalty-fee quality-fee))
  )
    ;; Validate asset ID and conditions
    (asserts! (<= asset-id (var-get asset-counter)) ERR-ASSET-ID-INVALID)
    (asserts! (is-eq (get licensee asset-data) (some tx-sender)) ERR-UNAUTHORIZED)
    (asserts! (is-eq (get listing-status asset-data) "LICENSED") ERR-ASSET-UNAVAILABLE)
    (asserts! (>= (- block-height (unwrap! (get purchase-block asset-data) ERR-ASSET-UNAVAILABLE)) 
                (get license-period asset-data)) ERR-LICENSING-IN-PROGRESS)
    (asserts! (>= licensee-balance total-fee) ERR-INSUFFICIENT-FUNDS)
    
    ;; Process payment
    (map-set credit-balances tx-sender (- licensee-balance total-fee))
    (map-set credit-balances (get creator asset-data) 
      (+ (default-to u0 (map-get? credit-balances (get creator asset-data))) 
         total-fee)
    )
    
    ;; Update creator reputation
    (let ((current-score (default-to u0 (map-get? creator-reputation 
                          (get creator asset-data)))))
      (map-set creator-reputation
        (get creator asset-data)
        (+ current-score u1)
      )
    )
    
    ;; Mark asset as fully transferred
    (map-set asset-registry { asset-id: asset-id } (merge asset-data { listing-status: "TRANSFERRED" }))
    (ok true)
  )
)

(define-public (delist-asset (asset-id uint))
  (let (
    (asset-data (unwrap! (map-get? asset-registry { asset-id: asset-id }) ERR-ASSET-UNAVAILABLE))
  )
    ;; Validate asset ID and authorization
    (asserts! (<= asset-id (var-get asset-counter)) ERR-ASSET-ID-INVALID)
    (asserts! (is-eq (get creator asset-data) tx-sender) ERR-UNAUTHORIZED)
    (asserts! (is-eq (get listing-status asset-data) "AVAILABLE") ERR-ASSET-UNAVAILABLE)
    
    ;; Mark asset as delisted
    (map-set asset-registry { asset-id: asset-id } (merge asset-data { listing-status: "DELISTED" }))
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

(define-read-only (get-creator-rating (creator principal))
  (default-to u0 (map-get? creator-reputation creator))
)

(define-read-only (view-consumer-assets (consumer principal))
  (default-to (list) (map-get? consumer-purchase-history consumer))
)

;; Calculate quality multiplier
(define-read-only (calculate-quality-bonus (quality-tier uint))
  (if (and (>= quality-tier u1) (<= quality-tier u5))
      (* quality-tier u1)
      u0)  ;; Return a default value if quality tier is invalid
)