#!/bin/bash
# Ação "Desinstalar" do clique-direito nos ícones do Plank (Desktop
# Action dos atalhos curados). Nativo do Tarsila OS — não depende da
# Tarsila Store. Se a Store estiver instalada, delega para o tarsila-pkg
# (preserva a segurança do catálogo); se não, usa apt-get remove direto.
DESKTOP="${1:-}"
[ -f "$DESKTOP" ] || exit 1

NATIVES=/usr/share/tarsila/native-apps.txt
DOCK="$HOME/.config/plank/dock1/launchers"
NOME=$(sed -n 's/^Name=//p' "$DESKTOP" | head -1)
base=$(basename "$DESKTOP")

recusa() {
  yad --info --center --fixed --title="Desinstalar" --width=400 --text="$1"
  exit 0
}

grep -qxF "$base" "$NATIVES" 2>/dev/null \
  && recusa "'$NOME' faz parte do sistema e não pode ser desinstalado."

exec_line=$(sed -n 's/^Exec=//p' "$DESKTOP" | head -1)
case "$exec_line" in
  *--app=*) recusa "'$NOME' é um atalho do sistema e não pode ser desinstalado por aqui." ;;
esac

package=$(sed -n 's/^X-Package=//p' "$DESKTOP" | head -1)
if [ -z "$package" ]; then
  cmd=${exec_line%% *}
  path=$(command -v "$cmd" 2>/dev/null)
  [ -n "$path" ] && package=$(dpkg -S "$path" 2>/dev/null | cut -d: -f1 | head -1)
fi
[ -z "$package" ] && recusa "'$NOME' faz parte do sistema e não pode ser desinstalado."

yad --question --center --fixed --title="Desinstalar" --width=400 \
    --text="Deseja realmente desinstalar '$NOME'?" || exit 0

# App do catálogo sai sem senha: o tarsila-pkg tem regra NOPASSWD própria,
# que é segura porque ele valida o pacote contra a whitelist antes de agir.
# Qualquer outro app passa pelo apt-get, que NÃO tem regra NOPASSWD em lugar
# nenhum do projeto -- e por isso precisa da senha. Antes daqui a chamada era
# "sudo -n apt-get" (não-interativo): falhava sempre, e em silêncio.
SENHA=""
if [ -x /opt/tarsila-store/bin/tarsila-pkg ] && grep -qxF "$package" /opt/tarsila-store/whitelist.txt 2>/dev/null; then
  VIA_CATALOGO=1
else
  VIA_CATALOGO=0
  SENHA=$(/usr/local/bin/tarsila-pedir-senha \
            "Desinstalar '$NOME' exige a senha de administrador.") || exit 0
fi

(
  erro=""
  if [ "$VIA_CATALOGO" = 1 ]; then
    if erro=$(sudo -n /opt/tarsila-store/bin/tarsila-pkg remove "$package" 2>&1 >/dev/null); then
      ok=1
    else
      ok=0
    fi
  else
    if erro=$(printf '%s\n' "$SENHA" \
              | sudo -S -k -p "" apt-get remove -y "$package" 2>&1 >/dev/null); then
      ok=1
    else
      ok=0
    fi
  fi

  if [ "$ok" = 1 ]; then
    item=$(grep -l "file://$DESKTOP" "$DOCK"/*.dockitem 2>/dev/null | head -1)
    if [ -n "$item" ]; then
      pkill -x plank
      sleep 0.5
      rm -f "$item"
      /usr/local/bin/tarsila-dock-apply.sh 2>/dev/null
      nohup plank >/dev/null 2>&1 &
    fi
    command -v notify-send >/dev/null \
      && notify-send "Desinstalação concluída" "'$NOME' foi removido."
  else
    # O motivo importa: antes a saída ia toda para /dev/null e a falha era
    # indistinguível de "não aconteceu nada".
    detalhe=$(printf '%s' "$erro" | tail -2 | tr '\n' ' ')
    command -v notify-send >/dev/null \
      && notify-send "Desinstalação falhou" \
                     "Não foi possível remover '$NOME'. ${detalhe:-Verifique o log.}"
  fi
) &
yad --info --center --fixed --title="Desinstalando" --timeout=3 \
    --text="A desinstalação de '$NOME' está em andamento em segundo plano."
exit 0