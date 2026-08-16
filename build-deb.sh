#!/bin/bash
# build-deb.sh — Gera tarsila-app-management_<versao>_all.deb
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PKG_NAME="tarsila-app-management"
# A versao vem do DEBIAN/control, que e a fonte unica. Estava escrita a mao
# aqui tambem e as duas ja tinham divergido: o control dizia 1.1.0 e o arquivo
# saia com 1.0.0 no nome -- o mesmo pacote com dois numeros.
VERSION="${1:-$(sed -n 's/^Version: *//p' "$SCRIPT_DIR/DEBIAN/control" | head -1)}"
[ -n "$VERSION" ] || { echo "ERRO: sem Version: em DEBIAN/control" >&2; exit 1; }
DEB="${PKG_NAME}_${VERSION}_all.deb"
BUILD_DIR="$(mktemp -d)"

cleanup() { rm -rf "$BUILD_DIR"; }
trap cleanup EXIT

echo "==> Construindo $DEB..."

cp -a "$SCRIPT_DIR/DEBIAN" "$BUILD_DIR/"
mkdir -p "$BUILD_DIR/usr/local/bin"
mkdir -p "$BUILD_DIR/usr/share/applications"

install -m 755 "$SCRIPT_DIR/src/usr/local/bin/tarsila-app-uninstall.sh"  "$BUILD_DIR/usr/local/bin/"
install -m 755 "$SCRIPT_DIR/src/usr/local/bin/tarsila-appfinder-yad.sh"   "$BUILD_DIR/usr/local/bin/"
install -m 755 "$SCRIPT_DIR/src/usr/local/bin/tarsila-deb-gui.py"         "$BUILD_DIR/usr/local/bin/"
install -m 755 "$SCRIPT_DIR/src/usr/local/bin/tarsila-deb-instalar"       "$BUILD_DIR/usr/local/bin/"
install -m 755 "$SCRIPT_DIR/src/usr/local/bin/tarsila-atalho-criar"       "$BUILD_DIR/usr/local/bin/"
install -m 755 "$SCRIPT_DIR/src/usr/local/bin/tarsila-pedir-senha"        "$BUILD_DIR/usr/local/bin/"
install -m 644 "$SCRIPT_DIR/src/usr/share/applications/tarsila-deb-installer.desktop" "$BUILD_DIR/usr/share/applications/"
install -m 644 "$SCRIPT_DIR/src/usr/share/applications/tarsila-appfinder-yad.desktop" "$BUILD_DIR/usr/share/applications/"

chmod 755 "$BUILD_DIR/DEBIAN/postinst"

dpkg-deb --build --root-owner-group "$BUILD_DIR" "$DEB"
echo "==> $DEB gerado."