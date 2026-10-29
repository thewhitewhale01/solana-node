#!/usr/bin/env bash
# validator.sh — launches agave-validator as a NON-VOTING RPC node.
# Edit flags here, then: systemctl restart sol.service
# Stage 2 (Yellowstone gRPC): uncomment the --geyser-plugin-config line once the plugin is built.

set -euo pipefail
export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"
export RUST_LOG="${RUST_LOG:-solana=info,solana_metrics=warn}"

LEDGER=/mnt/ledger
ACCOUNTS=/mnt/accounts
SNAPSHOTS=$HOME/snapshots
LOGFILE=$HOME/log/validator.log

mkdir -p "$SNAPSHOTS" "$HOME/log"

# Trusted sources for snapshots (Anza / Solana Foundation mainnet-beta known validators)
KNOWN=(
  --known-validator 7Np41oeYqPefeNQEHSv1UDhYrehxin3NStELsSKCT4K2
  --known-validator GdnSyH3YtwcxFvQrVVJMm1JhTS4QVX7MFsX56uJLUfiZ
  --known-validator DE1bawNcRJB9rVm3buyMVfr8mBEoyyu73NBovf2oXJsJ
  --known-validator CakcnaRDHka2gXyfbEd2d3xsvkJkqsLw2akB3zsN1D2S
)

exec agave-validator \
  --identity "$HOME/validator-keypair.json" \
  --no-voting \
  --ledger "$LEDGER" \
  --accounts "$ACCOUNTS" \
  --snapshots "$SNAPSHOTS" \
  --log "$LOGFILE" \
  --entrypoint entrypoint.mainnet-beta.solana.com:8001 \
  --entrypoint entrypoint2.mainnet-beta.solana.com:8001 \
  --entrypoint entrypoint3.mainnet-beta.solana.com:8001 \
  --expected-genesis-hash 5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d \
  "${KNOWN[@]}" \
  --only-known-rpc \
  --rpc-port 8899 \
  --rpc-bind-address 127.0.0.1 \
  --private-rpc \
  --full-rpc-api \
  --enable-rpc-transaction-history \
  --enable-extended-tx-metadata-storage \
  --rpc-pubsub-enable-block-subscription \
  --account-index program-id \
  --account-index spl-token-owner \
  --account-index spl-token-mint \
  --dynamic-port-range 8000-8020 \
  --limit-ledger-size \
  --wal-recovery-mode skip_any_corrupted_record \
  --maximum-snapshot-download-abort 5 \
  --no-port-check
  # --geyser-plugin-config "$HOME/yellowstone/config.json"
