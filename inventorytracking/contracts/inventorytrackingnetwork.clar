;; Inventory Tracking Network
;; A comprehensive blockchain solution for warehouse and inventory management across multiple locations

;; Error constants
(define-constant ERR_PERMISSION_DENIED (err u400))
(define-constant ERR_ITEM_ALREADY_EXISTS (err u401))
(define-constant ERR_ITEM_NOT_FOUND (err u402))
(define-constant ERR_INVALID_LOCATION (err u403))
(define-constant ERR_WAREHOUSE_NOT_FOUND (err u404))
(define-constant ERR_INVALID_MOVEMENT (err u405))
(define-constant ERR_INVALID_INPUT (err u406))
(define-constant ERR_EMPTY_VALUE (err u407))

;; Inventory states
(define-data-var next-item-id uint u1)

;; Item location states
(define-constant LOCATION_RECEIVED u1)
(define-constant LOCATION_STORED u2)
(define-constant LOCATION_PICKED u3)
(define-constant LOCATION_SHIPPED u4)

;; Operator roles
(define-constant ROLE_RECEIVER u1)
(define-constant ROLE_STORER u2)
(define-constant ROLE_PICKER u3)
(define-constant ROLE_SHIPPER u4)

;; Data structures

;; Operator registry
(define-map operators principal 
  {
    role: uint,
    warehouse-name: (string-utf8 50),
    is-active: bool,
    registration-time: uint
  }
)

;; Inventory items
(define-map inventory-items uint 
  {
    item-name: (string-utf8 100),
    receiving-operator: principal,
    current-location: uint,
    current-operator: principal,
    received-time: uint,
    last-movement: uint
  }
)

;; Movement history
(define-map item-movements (tuple (item-id uint) (movement-id uint))
  {
    location: uint,
    handler: principal,
    warehouse-section: (string-utf8 100),
    movement-time: uint,
    movement-notes: (string-utf8 200)
  }
)

;; Movement counter per item
(define-map item-movement-count uint uint)

;; Network administrator
(define-data-var network-admin principal tx-sender)

;; System functions

;; Network initialization
(define-public (initialize-network)
  (begin
    (asserts! (is-eq tx-sender (var-get network-admin)) ERR_PERMISSION_DENIED)
    (ok true)
  )
)

;; Input validation functions
(define-private (validate-role (role uint))
  (or (is-eq role ROLE_RECEIVER) 
      (is-eq role ROLE_STORER) 
      (is-eq role ROLE_PICKER)
      (is-eq role ROLE_SHIPPER))
)

(define-private (validate-item-id (item-id uint))
  (> item-id u0)
)

(define-private (validate-location (location uint))
  (and (>= location LOCATION_RECEIVED) (<= location LOCATION_SHIPPED))
)

(define-private (validate-warehouse-name (input (string-utf8 50)))
  (> (len input) u0)
)

(define-private (validate-item-name (input (string-utf8 100)))
  (> (len input) u0)
)

(define-private (validate-movement-notes (input (string-utf8 200)))
  (>= (len input) u0)
)

;; Operator registration
(define-public (register-operator (role uint) (warehouse-name (string-utf8 50)))
  (begin
    ;; Validate inputs
    (asserts! (validate-role role) ERR_INVALID_LOCATION)
    (asserts! (validate-warehouse-name warehouse-name) ERR_EMPTY_VALUE)
    
    ;; Check for existing registration
    (asserts! (is-none (map-get? operators tx-sender)) ERR_ITEM_ALREADY_EXISTS)
    
    ;; Register operator
    (map-set operators tx-sender {
      role: role,
      warehouse-name: (unwrap-panic (as-max-len? warehouse-name u50)),
      is-active: true,
      registration-time: stacks-block-height
    })
    
    (ok true)
  )
)

;; Item receiving
(define-public (receive-item (item-name (string-utf8 100)) (warehouse-section (string-utf8 100)) (movement-notes (string-utf8 200)))
  (begin
    ;; Validate inputs
    (asserts! (validate-item-name item-name) ERR_EMPTY_VALUE)
    (asserts! (validate-item-name warehouse-section) ERR_EMPTY_VALUE)
    (asserts! (validate-movement-notes movement-notes) ERR_INVALID_INPUT)
    
    (let 
      (
        (operator (unwrap! (map-get? operators tx-sender) ERR_WAREHOUSE_NOT_FOUND))
        (item-id (var-get next-item-id))
      )
      
      ;; Verify operator role
      (asserts! (is-eq (get role operator) ROLE_RECEIVER) ERR_PERMISSION_DENIED)
      
      ;; Create item record
      (map-set inventory-items item-id {
        item-name: (unwrap-panic (as-max-len? item-name u100)),
        receiving-operator: tx-sender,
        current-location: LOCATION_RECEIVED,
        current-operator: tx-sender,
        received-time: stacks-block-height,
        last-movement: stacks-block-height
      })
      
      ;; Log initial movement
      (map-set item-movements {item-id: item-id, movement-id: u0} {
        location: LOCATION_RECEIVED,
        handler: tx-sender,
        warehouse-section: (unwrap-panic (as-max-len? warehouse-section u100)),
        movement-time: stacks-block-height,
        movement-notes: (unwrap-panic (as-max-len? movement-notes u200))
      })
      
      ;; Initialize movement counter
      (map-set item-movement-count item-id u1)
      
      ;; Increment item ID
      (var-set next-item-id (+ item-id u1))
      
      (ok item-id)
    )
  )
)

;; Item movement
(define-public (move-item (item-id uint) (new-location uint) (warehouse-section (string-utf8 100)) (movement-notes (string-utf8 200)))
  (begin
    ;; Validate inputs
    (asserts! (validate-item-id item-id) ERR_INVALID_INPUT)
    (asserts! (validate-location new-location) ERR_INVALID_LOCATION)
    (asserts! (validate-item-name warehouse-section) ERR_EMPTY_VALUE)
    (asserts! (validate-movement-notes movement-notes) ERR_INVALID_INPUT)
    
    (let 
      (
        (operator (unwrap! (map-get? operators tx-sender) ERR_WAREHOUSE_NOT_FOUND))
        (item (unwrap! (map-get? inventory-items item-id) ERR_ITEM_NOT_FOUND))
        (current-location (get current-location item))
        (movement-count (default-to u0 (map-get? item-movement-count item-id)))
        (next-movement-id movement-count)
      )
      
      ;; Validate movement
      (asserts! (is-valid-movement (get role operator) current-location new-location) ERR_INVALID_MOVEMENT)
      
      ;; Update item record
      (map-set inventory-items item-id (merge item {
        current-location: new-location,
        current-operator: tx-sender,
        last-movement: stacks-block-height
      }))
      
      ;; Log movement
      (map-set item-movements {item-id: item-id, movement-id: next-movement-id} {
        location: new-location,
        handler: tx-sender,
        warehouse-section: (unwrap-panic (as-max-len? warehouse-section u100)),
        movement-time: stacks-block-height,
        movement-notes: (unwrap-panic (as-max-len? movement-notes u200))
      })
      
      ;; Update movement counter
      (map-set item-movement-count item-id (+ movement-count u1))
      
      (ok true)
    )
  )
)

;; Movement validation
(define-private (is-valid-movement (role uint) (current-location uint) (new-location uint))
  (or
    ;; Receiver can move from received to stored
    (and (is-eq role ROLE_RECEIVER) 
         (is-eq current-location LOCATION_RECEIVED) 
         (is-eq new-location LOCATION_STORED))
    
    ;; Storer can move from stored to picked
    (and (is-eq role ROLE_STORER) 
         (is-eq current-location LOCATION_STORED) 
         (is-eq new-location LOCATION_PICKED))
    
    ;; Picker can move from picked to shipped
    (and (is-eq role ROLE_PICKER) 
         (is-eq current-location LOCATION_PICKED) 
         (is-eq new-location LOCATION_SHIPPED))
  )
)

;; Query functions

;; Get item details
(define-read-only (get-item-details (item-id uint))
  (map-get? inventory-items item-id)
)

;; Get operator details
(define-read-only (get-operator-details (operator-address principal))
  (map-get? operators operator-address)
)

;; Get movement details
(define-read-only (get-movement-details (item-id uint) (movement-id uint))
  (map-get? item-movements {item-id: item-id, movement-id: movement-id})
)

;; Get movement count
(define-read-only (get-movement-count (item-id uint))
  (default-to u0 (map-get? item-movement-count item-id))
)

;; Verify item exists
(define-read-only (verify-item-exists (item-id uint))
  (is-some (map-get? inventory-items item-id))
)

;; Get location description
(define-read-only (get-location-description (location-id uint))
  (if (is-eq location-id LOCATION_RECEIVED)
      "Received"
      (if (is-eq location-id LOCATION_STORED)
          "Stored"
          (if (is-eq location-id LOCATION_PICKED)
              "Picked"
              (if (is-eq location-id LOCATION_SHIPPED)
                  "Shipped"
                  "Unknown"
              )
          )
      )
  )
)

;; Get role description
(define-read-only (get-role-description (role-id uint))
  (if (is-eq role-id ROLE_RECEIVER)
      "Receiver"
      (if (is-eq role-id ROLE_STORER)
          "Storer"
          (if (is-eq role-id ROLE_PICKER)
              "Picker"
              (if (is-eq role-id ROLE_SHIPPER)
                  "Shipper"
                  "Unknown"
              )
          )
      )
  )
)
