;; Wrapped STX (WSTX) - Clarity
;; 1:1 Wrapped STX token. Users deposit STX to mint WSTX, burn WSTX to receive STX.
;; No external trait implementation included to keep this contract self-contained.
;; No external trait implementation included to keep this contract self-contained.

;; -----------------------
;; Constants / Error codes
;; -----------------------
(define-constant ERR_NOT_ENOUGH_BALANCE (err u100))
(define-constant ERR_ZERO_AMOUNT        (err u101))
(define-constant ERR_NOT_OWNER          (err u102))
(define-constant ERR_INSUFFICIENT_STX   (err u103))
(define-constant ERR_TRANSFER_FAILED    (err u104))
(define-constant ERR_INVALID_SENDER     (err u105))

(define-constant TOKEN_NAME    "Wrapped STX")
(define-constant TOKEN_SYMBOL  "WSTX")
(define-constant TOKEN_DECIMALS u6) ;; follow STX microstacks precision

;; -----------------------
;; State variables / maps
;; -----------------------
(define-data-var total-supply uint u0)                    ;; total WSTX outstanding (in microstacks)
(define-map balances principal uint)                      ;; WSTX balances
(define-data-var total-stx-locked uint u0)                ;; STX locked in contract (microstacks)

;; Optional audit maps
(define-map deposits uint (tuple (depositor principal) (amount uint) (block uint)))
(define-data-var deposit-count uint u0)

(define-map withdrawals uint (tuple (recipient principal) (amount uint) (block uint)))
(define-data-var withdrawal-count uint u0)

;; -----------------------
;; Helpers
;; -----------------------
(define-read-only (is-valid-amount (a uint))
  (ok (> a u0))
)

;; internal mint: increases balance and total supply (used when wrapping)
(define-private (mint (who principal) (amount uint))
  (let ((prev (default-to u0 (map-get? balances who))))
    ;; Prevent potential overflow
    (asserts! (>= (+ prev amount) prev) ERR_TRANSFER_FAILED)
    (map-set balances who (+ prev amount))
    (var-set total-supply (+ (var-get total-supply) amount))
    (ok (tuple (who who) (amount amount)))
  )
)

;; internal burn: decreases balance and total supply (used when unwrapping)
(define-private (burn (who principal) (amount uint))
  (let ((prev (default-to u0 (map-get? balances who))))
    (asserts! (>= prev amount) ERR_NOT_ENOUGH_BALANCE)
    (map-set balances who (- prev amount))
    (var-set total-supply (- (var-get total-supply) amount))
    (ok (tuple (who who) (amount amount)))
  )
)

;; -----------------------
;; Payable entrypoint: wrap (deposit STX and receive WSTX)
;; Caller must attach STX to the call; stx-get-transfer-amount returns attached amount.
;; -----------------------
(define-public (wrap (amount uint))
  (begin
    (asserts! (> amount u0) ERR_ZERO_AMOUNT)
    ;; Transfer STX from sender to contract
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    ;; mint equivalent WSTX to tx-sender
    (try! (mint tx-sender amount))
    
    ;; update internal locked STX tracker
    (var-set total-stx-locked (+ (var-get total-stx-locked) amount))

    ;; record deposit
    (let ((id (+ (var-get deposit-count) u1)))
      (map-set deposits id (tuple (depositor tx-sender) (amount amount) (block burn-block-height)))
      (var-set deposit-count id)
    )

    (ok (tuple (action "wrap") (who tx-sender) (amount amount) (new-total (var-get total-supply))))
  )
)

;; -----------------------
;; Unwrap: burn WSTX and transfer STX back to user
;; -----------------------
(define-public (unwrap (amount uint))
  (begin
    (asserts! (> amount u0) ERR_ZERO_AMOUNT)

    ;; ensure caller has enough WSTX and burn
    (try! (burn tx-sender amount))
    
    ;; check contract has enough locked STX recorded
    (let ((locked (var-get total-stx-locked)))
      (asserts! (>= locked amount) ERR_INSUFFICIENT_STX)

      ;; perform STX transfer from contract to caller
      (try! (stx-transfer? amount (as-contract tx-sender) tx-sender))
      
      ;; update locked tracker
      (var-set total-stx-locked (- locked amount))

      ;; record withdrawal
      (let ((id (+ (var-get withdrawal-count) u1)))
        (map-set withdrawals id (tuple (recipient tx-sender) (amount amount) (block burn-block-height)))
        (var-set withdrawal-count id)
      )

      (ok (tuple (action "unwrap") (who tx-sender) (amount amount) (new-total (var-get total-supply))))
    )
  )
)

;; -----------------------
;; Standard token transfer between principals
;; -----------------------
(define-public (transfer (recipient principal) (amount uint))
  (let ((sender-balance (default-to u0 (map-get? balances tx-sender)))
        (recipient-balance (default-to u0 (map-get? balances recipient))))
    (begin
      (asserts! (> amount u0) ERR_ZERO_AMOUNT)
      (asserts! (>= sender-balance amount) ERR_NOT_ENOUGH_BALANCE)
      ;; Prevent potential overflow
      (asserts! (>= (+ recipient-balance amount) recipient-balance) ERR_TRANSFER_FAILED)
      (map-set balances tx-sender (- sender-balance amount))
      (map-set balances recipient (+ recipient-balance amount))
      (ok true)
    )
  )
)

;; -----------------------
;; Read-only views
;; -----------------------
(define-read-only (get-name) (ok TOKEN_NAME))
(define-read-only (get-symbol) (ok TOKEN_SYMBOL))
(define-read-only (get-decimals) (ok TOKEN_DECIMALS))

(define-read-only (get-balance (who principal))
  (ok (default-to u0 (map-get? balances who)))
)

(define-read-only (get-total-supply)
  (ok (var-get total-supply))
)

(define-read-only (get-total-stx-locked)
  ;; internal tracker for how much STX the contract is holding for users
  (ok (var-get total-stx-locked))
)

(define-read-only (get-deposit (id uint))
  (ok (map-get? deposits id))
)

(define-read-only (get-withdrawal (id uint))
  (ok (map-get? withdrawals id))
)

(define-read-only (get-deposit-count) (ok (var-get deposit-count)))
(define-read-only (get-withdrawal-count) (ok (var-get withdrawal-count)))
