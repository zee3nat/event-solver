;; event-solver
;; This contract manages event coordination, resource allocation, and participant interactions
;; on the Stacks blockchain. It provides a comprehensive system for event organizers to
;; create, manage, and track complex event logistics with transparent and secure mechanisms.
;; The contract facilitates dynamic workflow management and fair participation tracking.
;; Error Constants
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ASSET-NOT-FOUND (err u101))
(define-constant ERR-ALREADY-REGISTERED (err u102))
(define-constant ERR-NOT-OWNER (err u103))
(define-constant ERR-NOT-FOR-SALE (err u104))
(define-constant ERR-INSUFFICIENT-FUNDS (err u105))
(define-constant ERR-INVALID-PRICE (err u106))
(define-constant ERR-NO-LISTING (err u107))
(define-constant ERR-METADATA-TOO-LONG (err u108))
(define-constant ERR-INVALID-ROYALTY (err u109))
;; Data Maps and Variables
;; Tracks the total number of assets registered
(define-data-var asset-counter uint u0)
;; Stores the essential data for each VR asset
(define-map assets
  { asset-id: uint }
  {
    owner: principal,
    creator: principal,
    metadata-url: (string-utf8 256),
    is-transferable: bool,
    royalty-percentage: uint,
    creation-height: uint,
  }
)
;; Stores extended metadata for each VR asset
(define-map asset-metadata
  { asset-id: uint }
  {
    name: (string-utf8 100),
    description: (string-utf8 500),
    dimensions: {
      x: uint,
      y: uint,
      z: uint,
    },
    compatible-platforms: (list 20 (string-utf8 50)),
    content-rating: (string-utf8 20),
    file-type: (string-utf8 20),
  }
)
;; Tracks marketplace listings
(define-map asset-listings
  { asset-id: uint }
  {
    price: uint,
    listed-by: principal,
    listed-at: uint,
  }
)
;; Tracks transfers for each asset to maintain provenance history
;; Limited to the last 10 transfers for practical considerations
(define-map asset-transfers
  { asset-id: uint }
  { history: (list 10 {
    from: principal,
    to: principal,
    price: (optional uint),
    block-height: uint,
    tx-id: (buff 32),
  }) }
)
;; Private Functions
;; Get the current asset counter value and increment it
(define-private (get-and-increment-asset-id)
  (let ((current-id (var-get asset-counter)))
    (var-set asset-counter (+ current-id u1))
    current-id
  )
)

;; Calculate and distribute royalty payment
(define-private (handle-royalty
    (asset-id uint)
    (sale-price uint)
  )
  (let (
      (asset-data (unwrap! (map-get? assets { asset-id: asset-id }) ERR-ASSET-NOT-FOUND))
      (creator (get creator asset-data))
      (royalty-percentage (get royalty-percentage asset-data))
      (royalty-amount (/ (* sale-price royalty-percentage) u1000))
    )
    (if (and (> royalty-amount u0) (not (is-eq creator tx-sender)))
      (stx-transfer? royalty-amount tx-sender creator)
      (ok true)
    )
  )
)

;; Check if an asset exists and get its data
(define-private (get-asset-data (asset-id uint))
  (match (map-get? assets { asset-id: asset-id })
    asset-data (ok asset-data)
    ERR-ASSET-NOT-FOUND
  )
)

;; Check if sender is the asset owner
(define-private (check-is-owner (asset-id uint))
  (let ((asset-data (unwrap! (get-asset-data asset-id) ERR-ASSET-NOT-FOUND)))
    (if (is-eq tx-sender (get owner asset-data))
      (ok true)
      ERR-NOT-OWNER
    )
  )
)

;; Read-Only Functions
;; Get basic information about an asset
(define-read-only (get-asset-info (asset-id uint))
  (map-get? assets { asset-id: asset-id })
)

;; Get metadata for an asset
(define-read-only (get-asset-metadata-by-id (asset-id uint))
  (map-get? asset-metadata { asset-id: asset-id })
)

;; Check if an asset is listed for sale and get listing details
(define-read-only (get-asset-listing (asset-id uint))
  (map-get? asset-listings { asset-id: asset-id })
)

;; Get provenance history of an asset
(define-read-only (get-asset-history (asset-id uint))
  (default-to { history: (list) }
    (map-get? asset-transfers { asset-id: asset-id })
  )
)

;; Public Functions
;; Register a new VR asset
(define-public (register-asset
    (metadata-url (string-utf8 256))
    (name (string-utf8 100))
    (description (string-utf8 500))
    (dimensions {
      x: uint,
      y: uint,
      z: uint,
    })
    (compatible-platforms (list 20 (string-utf8 50)))
    (content-rating (string-utf8 20))
    (file-type (string-utf8 20))
    (is-transferable bool)
    (royalty-percentage uint)
  )
  (let (
      (asset-id (get-and-increment-asset-id))
      (creator tx-sender)
    )
    ;; Validate inputs
    (asserts! (<= (len metadata-url) u256) ERR-METADATA-TOO-LONG)
    (asserts! (<= royalty-percentage u500) ERR-INVALID-ROYALTY)
    ;; Max 50% royalty
    ;; Store the asset data
    (map-set assets { asset-id: asset-id } {
      owner: creator,
      creator: creator,
      metadata-url: metadata-url,
      is-transferable: is-transferable,
      royalty-percentage: royalty-percentage,
      creation-height: block-height,
    })
    ;; Store extended metadata
    (map-set asset-metadata { asset-id: asset-id } {
      name: name,
      description: description,
      dimensions: dimensions,
      compatible-platforms: compatible-platforms,
      content-rating: content-rating,
      file-type: file-type,
    })
    ;; Initialize transfer history with creation record
    ;; (record-transfer asset-id creator creator none)
    ;; Return the new asset ID
    (ok asset-id)
  )
)

;; Transfer ownership of an asset to another principal
(define-public (transfer-asset
    (asset-id uint)
    (recipient principal)
  )
  (let (
      (asset-data (unwrap! (map-get? assets { asset-id: asset-id }) ERR-ASSET-NOT-FOUND))
      (asset-owner (get owner asset-data))
    )
    ;; Verify ownership and transferability
    (asserts! (is-eq tx-sender asset-owner) ERR-NOT-OWNER)
    (asserts! (get is-transferable asset-data) ERR-NOT-AUTHORIZED)
    ;; Remove any existing listing
    (map-delete asset-listings { asset-id: asset-id })
    ;; Update ownership
    (map-set assets { asset-id: asset-id }
      (merge asset-data { owner: recipient })
    )
    ;; Record the transfer
    ;; (record-transfer asset-id tx-sender recipient none)
    (ok true)
  )
)

;; List an asset for sale
(define-public (list-asset-for-sale
    (asset-id uint)
    (price uint)
  )
  (let ((asset-data (unwrap! (map-get? assets { asset-id: asset-id }) ERR-ASSET-NOT-FOUND)))
    ;; Validate ownership and price
    (asserts! (is-eq tx-sender (get owner asset-data)) ERR-NOT-OWNER)
    (asserts! (get is-transferable asset-data) ERR-NOT-AUTHORIZED)
    (asserts! (> price u0) ERR-INVALID-PRICE)
    ;; Create listing
    (map-set asset-listings { asset-id: asset-id } {
      price: price,
      listed-by: tx-sender,
      listed-at: block-height,
    })
    (ok true)
  )
)

;; Remove asset listing
(define-public (cancel-asset-listing (asset-id uint))
  (let ((asset-data (unwrap! (map-get? assets { asset-id: asset-id }) ERR-ASSET-NOT-FOUND)))
    ;; Verify ownership
    (asserts! (is-eq tx-sender (get owner asset-data)) ERR-NOT-OWNER)
    ;; Check if there's a listing to cancel
    (asserts! (is-some (map-get? asset-listings { asset-id: asset-id }))
      ERR-NO-LISTING
    )
    ;; Remove listing
    (map-delete asset-listings { asset-id: asset-id })
    (ok true)
  )
)

;; Update asset metadata
(define-public (update-asset-metadata
    (asset-id uint)
    (metadata-url (string-utf8 256))
    (name (string-utf8 100))
    (description (string-utf8 500))
    (dimensions {
      x: uint,
      y: uint,
      z: uint,
    })
    (compatible-platforms (list 20 (string-utf8 50)))
    (content-rating (string-utf8 20))
    (file-type (string-utf8 20))
  )
  (let ((asset-data (unwrap! (map-get? assets { asset-id: asset-id }) ERR-ASSET-NOT-FOUND)))
    ;; Verify ownership
    (asserts! (is-eq tx-sender (get owner asset-data)) ERR-NOT-OWNER)
    ;; Update metadata URL in main asset data
    (map-set assets { asset-id: asset-id }
      (merge asset-data { metadata-url: metadata-url })
    )
    ;; Update extended metadata
    (map-set asset-metadata { asset-id: asset-id } {
      name: name,
      description: description,
      dimensions: dimensions,
      compatible-platforms: compatible-platforms,
      content-rating: content-rating,
      file-type: file-type,
    })
    (ok true)
  )
)

;; Update transferability and royalty settings
(define-public (update-asset-settings
    (asset-id uint)
    (is-transferable bool)
    (royalty-percentage uint)
  )
  (let ((asset-data (unwrap! (map-get? assets { asset-id: asset-id }) ERR-ASSET-NOT-FOUND)))
    ;; Verify ownership
    (asserts! (is-eq tx-sender (get owner asset-data)) ERR-NOT-OWNER)
    ;; Validate royalty percentage
    (asserts! (<= royalty-percentage u500) ERR-INVALID-ROYALTY)
    ;; Max 50% royalty
    ;; Update settings
    (map-set assets { asset-id: asset-id }
      (merge asset-data {
        is-transferable: is-transferable,
        royalty-percentage: royalty-percentage,
      })
    )
    (ok true)
  )
)

;; Verify asset ownership for external VR platforms
(define-read-only (verify-ownership
    (asset-id uint)
    (user principal)
  )
  (match (map-get? assets { asset-id: asset-id })
    asset-data (ok (is-eq user (get owner asset-data)))
    ERR-ASSET-NOT-FOUND
  )
)
