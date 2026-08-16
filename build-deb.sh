#!/bin/bash
# build-deb.sh — Gera DOIS pacotes a partir deste repositório:
#
#   tarsila-motor_<versao>_all.deb            criar e remover atalhos curados
#   tarsila-app-management_<versao>_all.deb   a interface gráfica
#
# POR QUE DOIS
# A Tarsila Store precisa criar e remover atalhos, mas não precisa do AppFinder
# nem do instalador gráfico de .deb. Antes ela resolvia isso carregando em
# motor/ uma cópia própria dos arquivos, instalada pelo postinst quando o
# app-management estava ausente. As duas cópias envelheceram separado e
# divergiram: a correção que fez a desinstalação pedir a senha, em vez de
# falhar calada com "sudo -n", entrou aqui e não lá.
#
# Agora o motor é um pacote, os dois dependem dele, e a fonte é uma só.
#
# Uso:
#   ./build-deb.sh            usa as versões de cada DEBIAN*/control
#   ./build-deb.sh 9.9.9      força a versão nos dois (builds pontuais)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FORCA_VERSAO="${1:-}"

# A versão vem do control, que é a fonte única. Escrita à mão aqui também,
# ela vira duas verdades que envelhecem separado -- foi o que aconteceu com o
# app-management: o control dizia 1.1.0 e o arquivo saía com 1.0.0 no nome.
versao_de() {
    local ctl="$1" v
    v="${FORCA_VERSAO:-$(sed -n 's/^Version: *//p' "$ctl" | head -1)}"
    [ -n "$v" ] || { echo "ERRO: sem Version: em $ctl" >&2; exit 1; }
    printf '%s\n' "$v"
}

# empacota <dir-DEBIAN> <nome-do-pacote> <arquivo>...
#
# Cada arquivo é "origem-relativa-ao-src:modo". O destino é o mesmo caminho,
# porque src/ espelha a raiz do sistema.
empacota() {
    local debian_dir="$1" pkg="$2"; shift 2
    local versao deb build
    versao="$(versao_de "$SCRIPT_DIR/$debian_dir/control")"
    deb="${pkg}_${versao}_all.deb"
    build="$(mktemp -d)"
    # shellcheck disable=SC2064  # queremos expandir $build agora
    trap "rm -rf '$build'" RETURN

    echo "==> Construindo $deb..."
    cp -a "$SCRIPT_DIR/$debian_dir" "$build/DEBIAN"
    [ -f "$build/DEBIAN/postinst" ] && chmod 755 "$build/DEBIAN/postinst"
    # O control precisa dizer a mesma versão do nome do arquivo, inclusive
    # quando ela foi forçada por argumento.
    sed -i "s/^Version: .*/Version: $versao/" "$build/DEBIAN/control"

    local item origem modo destino
    for item in "$@"; do
        origem="${item%%:*}"; modo="${item##*:}"
        destino="$build/$origem"
        mkdir -p "$(dirname "$destino")"
        install -m "$modo" "$SCRIPT_DIR/src/$origem" "$destino"
    done

    dpkg-deb --build --root-owner-group "$build" "$SCRIPT_DIR/$deb" >/dev/null
    echo "    $deb"
}

# ------------------------------------------------------------------ motor
# Criar e remover atalhos são duas metades de uma coisa só: todo atalho que o
# tarsila-atalho-criar gera embute uma ação "Desinstalar" apontando para o
# tarsila-app-uninstall.sh. Separá-los deixaria cada atalho com um item de
# menu morto. O tarsila-pedir-senha entra porque o desinstalador o chama para
# remover pacotes fora do catálogo da Store.
empacota DEBIAN-motor tarsila-motor \
    usr/local/bin/tarsila-atalho-criar:755 \
    usr/local/bin/tarsila-app-uninstall.sh:755 \
    usr/local/bin/tarsila-pedir-senha:755

# ------------------------------------------------------- interface gráfica
empacota DEBIAN tarsila-app-management \
    usr/local/bin/tarsila-appfinder-yad.sh:755 \
    usr/local/bin/tarsila-deb-gui.py:755 \
    usr/local/bin/tarsila-deb-instalar:755 \
    usr/share/applications/tarsila-deb-installer.desktop:644 \
    usr/share/applications/tarsila-appfinder-yad.desktop:644

echo "==> pronto."
