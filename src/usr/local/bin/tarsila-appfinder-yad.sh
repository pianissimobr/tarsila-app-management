#!/bin/bash
export NO_AT_BRIDGE=1
set -uo pipefail

CURATED_DIR="/usr/share/tarsila/applications"
GAMES_DIR="/usr/share/tarsila/games"
ICONS_DIR="/usr/share/tarsila/icons"
VERMAIS_DESKTOP="$CURATED_DIR/vermais-tarsila.desktop"
DOCK_DCONF_KEY="/net/launchpad/plank/docks/dock1/dock-items"
NATIVES_FILE="/usr/share/tarsila/native-apps.txt"
DOCK_MANAGER="/usr/local/bin/tarsila-dock-manager"
ICON_HELPER="/usr/local/bin/tarsila-icon-cache"
ICON_SIZE=48
# ONDE ABRIR: encostada no fim da Dock, subindo a partir dela, como um menu
# que sai do proprio botao "Ver mais".
#
# O calculo mora no tarsila-pos-dock, que o tarsila-gui instala, e e
# compartilhado com a Lixeira e os Ajustes. Ate 2026-08-15 havia AQUI uma
# copia inline dele -- 40 linhas com o mesmo Python embutido -- e as duas
# versoes ja tinham divergido: a copia compensava a decoracao do yad em
# (8, 64) e a tabela do pos-dock, em (9, 66). A janela abria dois pixels
# fora do lugar em relacao as outras duas telas.
#
# Num Debian sem o tarsila-gui o helper nao existe: a funcao falha, e quem
# chama cai no posicionamento padrao do yad (centralizado). E o comportamento
# correto para esse caso -- sem Dock do Tarsila, nao ha borda onde encostar.
# Tamanho com que a janela abre -- o que o usuario deixou ao ajustar na mao.
JANELA_LARG=405
JANELA_ALT=500
POS_DOCK="/usr/local/bin/tarsila-pos-dock"

posicao_junto_da_dock() {
    [ -x "$POS_DOCK" ] || return 1
    "$POS_DOCK" "$JANELA_LARG" "$JANELA_ALT" yad 2>/dev/null
}



# Apps nativos do sistema (Arquivos, Configuração, Store, Terminal,
# Lixeira): ficam sempre na Dock e fora desta grade - gerenciados so
# pela posicao no Gerenciar Dock.
declare -A native_desktops
if [ -f "$NATIVES_FILE" ]; then
    while IFS= read -r nb; do
        [ -n "$nb" ] && native_desktops["$CURATED_DIR/$nb"]=1
    done < "$NATIVES_FILE"
fi

# Detecta usuário real
if [ -n "${SUDO_USER:-}" ]; then
    REAL_USER="$SUDO_USER"
else
    REAL_USER="$(whoami)"
fi
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"
# A pasta guarda os .dockitem, que a tarsila-dock le. O nome "plank" no caminho
# e heranca: o formato e o lugar ficaram, o programa nao. Ate 17/08/2026 este
# mkdir era condicionado a `command -v plank` -- sem o Plank instalado, a pasta
# nunca era criada.
DOCK_CONFIG="$REAL_HOME/.config/plank/dock1/launchers/"
mkdir -p "$DOCK_CONFIG" 2>/dev/null || true

# Carrega apps curados
declare -A curated_apps
for f in "$CURATED_DIR"/*.desktop; do
    [ -e "$f" ] || continue
    name=$(sed -n 's/^Name=//p' "$f" | head -n1)
    [ -n "$name" ] && curated_apps["$name"]="$f"
done

# Os jogos moram numa pasta so deles. Antes o botao "Jogos" da Dock era o
# gerenciador de arquivos abrindo essa pasta: o usuario via arquivos .desktop
# soltos, nao uma tela de jogos. Agora sao a segunda aba desta janela.
declare -A game_apps
for f in "$GAMES_DIR"/*.desktop; do
    [ -e "$f" ] || continue
    name=$(sed -n 's/^Name=//p' "$f" | head -n1)
    [ -n "$name" ] && game_apps["$name"]="$f"
done

# Mapa unico para procurar o escolhido: os botoes (Executar, Desinstalar)
# ficam na janela de fora e valem para as duas abas, entao a busca pelo
# caminho gravado precisa enxergar aplicativos e jogos juntos.
declare -A todos_apps aba_de
for name in "${!curated_apps[@]}"; do
    todos_apps["$name"]="${curated_apps[$name]}"
    aba_de["$name"]="apps"
done
for name in "${!game_apps[@]}"; do
    todos_apps["$name"]="${game_apps[$name]}"
    aba_de["$name"]="jogos"
done

if [ ${#todos_apps[@]} -eq 0 ]; then
    yad --info --center --title="Aplicativos instalados" \
        --text="Nenhum aplicativo encontrado em:\n$CURATED_DIR" \
        --width=400 --height=100
    exit 0
fi

# Reescreve a ordem do dock no Plank ao vivo (sem precisar relogar),
# sempre deixando "Ver mais aplicativos" por último.
sync_dock_order() {
    command -v dconf &>/dev/null || return 0
    local f base items="" vermais_item=""
    for f in "$DOCK_CONFIG"/*.dockitem; do
        [ -e "$f" ] || continue
        base=$(basename "$f")
        if grep -q "^Launcher=file://$VERMAIS_DESKTOP\$" "$f" 2>/dev/null; then
            vermais_item="$base"
            continue
        fi
        items+="'$base', "
    done
    [ -n "$vermais_item" ] && items+="'$vermais_item', "
    [ -n "$items" ] || return 0
    items="[${items%, }]"
    dconf write "$DOCK_DCONF_KEY" "$items" 2>/dev/null || true
}

# Avisa a Dock de que a lista mudou. Ela observa a pasta dos .dockitem por
# inotify e se remonta sozinha em ~400 ms, entao aqui basta reescrever a ordem.
#
# Ate 17/08/2026 esta funcao chamava-se restart_plank e fazia o ritual da epoca:
# `pkill -x plank`, sleep 0,3, dock-apply, `nohup plank &`. Existia porque o
# Plank so carregava item novo ao iniciar -- a descoberta ao vivo dele tinha o
# bug do Launcher= vazio. O Plank saiu em 16/08 e a funcao inteira virou no-op,
# barrada pelo `command -v plank` da primeira linha.
avisa_a_dock() {
    if [ -x /usr/local/bin/tarsila-dock-apply.sh ]; then
        /usr/local/bin/tarsila-dock-apply.sh 2>/dev/null
    fi
}

uninstall_app() {
    local app_name="$1"
    local desktop_file="${todos_apps[$app_name]}"
    local exec_line exec_cmd exec_path package_name=""

    exec_line=$(sed -n 's/^Exec=//p' "$desktop_file" | head -n1)
    exec_cmd=${exec_line%% *}

    # Atalhos web (chromium --app=URL) não são um pacote próprio:
    # resolver pelo Exec= apontaria para o navegador, e "desinstalar"
    # a Agenda removeria o Chromium inteiro.
    if [[ "$exec_line" == *"--app="* ]]; then
        yad --info --center --fixed --title="Desinstalar" \
            --text="'$app_name' é um atalho do sistema e não pode ser desinstalado por aqui." \
            --width=380
        return 0
    fi

    if grep -q "^X-Package=" "$desktop_file" 2>/dev/null; then
        package_name=$(sed -n 's/^X-Package=//p' "$desktop_file" | head -n1)
    elif [ -n "$exec_cmd" ]; then
        # dpkg -S com caminho completo é uma busca exata; com o nome
        # solto seria busca por substring e podia acertar outro pacote.
        exec_path=$(command -v "$exec_cmd" 2>/dev/null || true)
        if [ -n "$exec_path" ]; then
            package_name=$(dpkg -S "$exec_path" 2>/dev/null | cut -d: -f1 | head -n1)
        fi
    fi

    # A desinstalação é nativa do Tarsila OS. Se a Store estiver
    # instalada, delega para o tarsila-pkg (preserva whitelist do
    # catálogo); se não, usa apt-get remove direto.
    if [ -z "$package_name" ]; then
        yad --info --center --fixed --title="Desinstalar" \
            --text="'$app_name' faz parte do sistema e não pode ser desinstalado." \
            --width=380
        return 0
    fi

    if ! yad --question --center --fixed --title="Desinstalar" \
             --text="Deseja realmente desinstalar '$app_name'?" \
             --width=400; then
        return 0
    fi
    # App do catalogo sai sem senha: o tarsila-pkg tem regra NOPASSWD propria,
    # segura porque ele valida o pacote contra a whitelist antes de agir.
    # Qualquer outro app passa pelo apt-get, que NAO tem regra NOPASSWD em
    # lugar nenhum do projeto -- e por isso precisa da senha. Ate 16/08 aqui
    # era "sudo -n apt-get": nao-interativo, falhava sempre e em silencio.
    # A senha e pedida ANTES de tirar o app da grade: se o usuario cancelar,
    # nada muda na tela.
    local senha="" via_catalogo=0
    if [ -x /opt/tarsila-store/bin/tarsila-pkg ] && grep -qxF "$package_name" /opt/tarsila-store/whitelist.txt 2>/dev/null; then
        via_catalogo=1
    else
        senha=$(/usr/local/bin/tarsila-pedir-senha \
                  "Desinstalar '$app_name' exige a senha de administrador.") || return 0
    fi
    # Tira o app da grade imediatamente (a janela reabre em seguida ja
    # sem ele; a remocao real continua em segundo plano). Se falhar, a
    # notificacao avisa e o app volta na proxima abertura do AppFinder.
    rm -f "$TMP_DIR/${aba_de[$app_name]}/${app_name}.desktop"
    (
        erro=""
        if [ "$via_catalogo" = 1 ]; then
            erro=$(sudo -n /opt/tarsila-store/bin/tarsila-pkg remove "$package_name" 2>&1 >/dev/null) && ok=1 || ok=0
        else
            erro=$(printf '%s\n' "$senha" \
                   | sudo -S -k -p "" apt-get remove -y "$package_name" 2>&1 >/dev/null) && ok=1 || ok=0
        fi
        if [ "$ok" = 1 ]; then
            # Tirar o icone da Dock ESTAVA dentro de um `if command -v plank`.
            # Sem o Plank instalado -- ou seja, desde 16/08/2026 -- desinstalar
            # um aplicativo por esta tela deixava o icone dele na Dock, com o
            # .desktop ja apagado. O usuario clicava e nao acontecia nada.
            find "$DOCK_CONFIG" -name "*.dockitem" 2>/dev/null | while read -r dockitem; do
                if grep -q "$(basename "$desktop_file")" "$dockitem" 2>/dev/null; then
                    rm -f "$dockitem"
                fi
            done
            sync_dock_order
            avisa_a_dock
            if command -v notify-send &>/dev/null; then
                notify-send "Desinstalação concluída" "'$app_name' foi removido."
            fi
        else
            # O motivo importa: antes a saida ia toda para /dev/null e a
            # falha era indistinguivel de "nao aconteceu nada".
            detalhe=$(printf '%s' "$erro" | tail -2 | tr '\n' ' ')
            if command -v notify-send &>/dev/null; then
                notify-send "Desinstalação falhou" \
                            "Não foi possível remover '$app_name'. ${detalhe:-Verifique o log.}"
            fi
        fi
    ) &
    yad --info --center --fixed --title="Desinstalando" \
        --text="A desinstalação de '$app_name' está em andamento em segundo plano." \
        --timeout=3
    return 0
}

# Preparação: criar diretório com arquivos .desktop para o YAD --icons
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT
SELECTION_FILE="$TMP_DIR/.selected"
# Chave que liga as abas a janela-caderno do yad.
YAD_KEY=$$

# O yad --icons desta versão não reporta de forma confiável o item
# selecionado quando ha varios botoes customizados na mesma janela
# (apenas o ultimo botao da lista responde a cliques nesse modo).
# Por isso cada .desktop gerado aqui, ao ser ativado (duplo clique),
# apenas grava o caminho do app original em SELECTION_FILE em vez de
# executa-lo direto - as acoes reais (Executar/Fixar/Desinstalar) sao
# escolhidas depois, num dialogo comum (nao-icones), onde os botoes
# funcionam normalmente em qualquer posicao.
mkdir -p "$TMP_DIR/wrappers" "$TMP_DIR/apps" "$TMP_DIR/jogos"

# Fase 1: resolve o ícone de cada app e monta o lote do cache de
# ícones. O yad 0.40 não redimensiona ícones que já vêm grandes
# (SVG/256px, ex.: MyPaint e Orage estouravam a grade); por isso todo
# ícone é pré-renderizado em PNG de ICON_SIZE px pelo tarsila-icon-cache
# (Python/GTK, que resolve nome de tema e redimensiona) num cache
# persistente por usuário - só ícones novos são renderizados de novo.
ICON_CACHE="$REAL_HOME/.cache/tarsila/icons$ICON_SIZE"
mkdir -p "$ICON_CACHE" 2>/dev/null || true
ICON_BATCH="$TMP_DIR/.icon-batch"
declare -A tile_icon_spec tile_icon_png
for name in "${!todos_apps[@]}"; do
    desktop_file="${todos_apps[$name]}"
    # "Ver mais aplicativos" é o próprio botão que abre esta tela - não
    # faz sentido listá-lo como uma opção dentro dela mesma. Apps
    # nativos também ficam de fora (sempre na Dock, ver native-apps.txt).
    [ "$desktop_file" = "$VERMAIS_DESKTOP" ] && continue
    [ -n "${native_desktops[$desktop_file]:-}" ] && continue
    icon=$(grep '^Icon=' "$desktop_file" | head -n1 | cut -d= -f2)
    if [ -z "$icon" ]; then
        icon="application-x-executable"
    elif [[ ! "$icon" =~ ^/ ]]; then
        # Se não for absoluto, procura primeiro na pasta de ícones do
        # Tarsila; se não achar, mantém o nome como está (em vez de
        # cair para um genérico) - é um nome de ícone de tema (ex.:
        # x-office-document, application-pdf) que o tema de ícones do
        # sistema (Papirus) resolve sozinho.
        if [ -f "$ICONS_DIR/${icon}.png" ]; then
            icon="$ICONS_DIR/${icon}.png"
        elif [ -f "$ICONS_DIR/${icon}.svg" ]; then
            icon="$ICONS_DIR/${icon}.svg"
        fi
    fi
    tile_icon_spec["$name"]="$icon"
    cached="$ICON_CACHE/$(printf '%s' "$icon" | md5sum | cut -d' ' -f1).png"
    tile_icon_png["$name"]="$cached"
    if [ ! -s "$cached" ] || { [[ "$icon" == /* ]] && [ "$icon" -nt "$cached" ]; }; then
        printf '%s\t%s\t%d\n' "$icon" "$cached" "$ICON_SIZE" >> "$ICON_BATCH"
    fi
done
if [ -s "$ICON_BATCH" ] && [ -x "$ICON_HELPER" ]; then
    "$ICON_HELPER" < "$ICON_BATCH" >/dev/null 2>&1 || true
fi

# Fase 2: gera os .desktop da grade, usando o PNG normalizado quando o
# cache deu certo (senão cai no ícone original, como antes).
wrapper_i=0
for name in "${!tile_icon_spec[@]}"; do
    desktop_file="${todos_apps[$name]}"
    icon="${tile_icon_spec[$name]}"
    [ -s "${tile_icon_png[$name]}" ] && icon="${tile_icon_png[$name]}"
    # Script wrapper dedicado: evita as regras de citação do campo
    # Exec= do formato .desktop (diferentes das do shell), que quebravam
    # ao embutir aspas/variáveis direto na linha Exec.
    wrapper_i=$((wrapper_i + 1))
    wrapper="$TMP_DIR/wrappers/$wrapper_i.sh"
    cat > "$wrapper" << EOF
#!/bin/sh
# Um clique marca o item (e o que os botoes Executar/Desinstalar leem).
# DOIS cliques seguidos no MESMO item abrem o aplicativo, como em qualquer
# gerenciador de arquivos.
#
# Por que aqui e nao numa opcao do yad: no modo --icons ele so oferece
# --single-click (ativar com um clique) ou o padrao (ativar com dois). Com
# dois, o clique simples deixaria de marcar, e os botoes perderiam a
# referencia do que esta selecionado. Guardando o instante do ultimo clique
# damos conta dos dois comportamentos.
AGORA=\$(date +%s%N)
ANTES=""; QUANDO=0
[ -f "$SELECTION_FILE" ] && ANTES=\$(cat "$SELECTION_FILE" 2>/dev/null)
[ -f "$SELECTION_FILE.quando" ] && QUANDO=\$(cat "$SELECTION_FILE.quando" 2>/dev/null)
printf '%s' "$desktop_file" > "$SELECTION_FILE"
printf '%s' "\$AGORA" > "$SELECTION_FILE.quando"
if [ "\$ANTES" = "$desktop_file" ] \\
   && [ \$(( (AGORA - QUANDO) / 1000000 )) -lt 600 ]; then
    gio launch "$desktop_file" >/dev/null 2>&1 &
    # Fecha a grade, como acontece ao usar o botao Executar. Matar o yad faz o
    # laco principal sair pelo mesmo caminho do X/Esc.
    pkill -x yad
fi
EOF
    chmod +x "$wrapper"
    # Cria arquivo .desktop no TMP_DIR
    cat > "$TMP_DIR/${aba_de[$name]}/${name}.desktop" << EOF
[Desktop Entry]
Name=$name
Exec=$wrapper
Icon=$icon
Type=Application
EOF
    chmod +x "$TMP_DIR/${aba_de[$name]}/${name}.desktop"
done

# Loop principal. O toque num app grava a seleção em SELECTION_FILE
# (ver comentário dos wrappers acima) e o item fica marcado; a ação vem
# dos botões da própria janela - não há mais diálogo intermediário.
# A janela só se encerra de vez no X/Esc ou ao Executar um app;
# Desinstalar e Gerenciar Dock voltam para ela (o "continue" reabre a
# grade na mesma hora, já relendo o TMP_DIR - por isso um app
# desinstalado some da grade ao voltar).
while true; do
    rm -f "$SELECTION_FILE"

    # Duas abas na mesma janela. Um menu de selecao nao caberia aqui: a
    # grade de icones do yad ocupa a janela inteira, entao a escolha teria de
    # virar um dialogo ANTES da grade - uma pergunta a mais toda vez que se
    # abre a tela. A aba nao custa passo nenhum.
    # Cada aba e um yad "plugado" na janela-caderno; os botoes ficam na janela
    # de fora e servem as duas, porque a escolha ja e gravada em
    # SELECTION_FILE pelos wrappers (ver comentario acima).
    yad --plug=$YAD_KEY --tabnum=1 --icons --read-dir="$TMP_DIR/apps" \
        --sort-by-name --icon-size=48 --item-width=100 \
        --icon-theme=Papirus --single-click 2>/dev/null &
    plug_apps=$!
    yad --plug=$YAD_KEY --tabnum=2 --icons --read-dir="$TMP_DIR/jogos" \
        --sort-by-name --icon-size=48 --item-width=100 \
        --icon-theme=Papirus --single-click 2>/dev/null &
    plug_jogos=$!
    sleep 1                 # as abas precisam existir antes da janela-caderno

    # --fixed trava o tamanho: sem isso a janela abriria redimensionavel e com
    # botao de maximizar, que nao fazem sentido numa grade de icones -- e o
    # usuario pediu os dois fora. O yad marca min=max nas dicas de tamanho e o
    # Openbox, vendo isso, ja esconde o botao e recusa o arrasto das bordas.
    POS=$(posicao_junto_da_dock 2>/dev/null)
    if [ -n "$POS" ]; then
        set -- $POS
        # --geometry em vez de --posx/--posy: o yad aplica a posicao DEPOIS de
        # mostrar a janela, e da o pulinho que se ve ao abrir. A geometria e
        # lida pelo GTK antes de exibir, entao a janela ja nasce no lugar --
        # e o que faz a Lixeira (programa nosso, que move antes de mostrar)
        # nao piscar.
        # Ja vem descontada a espessura da decoracao: o tarsila-pos-dock
        # recebe "yad" como terceiro argumento e aplica a compensacao da
        # tabela dele. Era aqui que a copia inline divergia (8,64 contra 9,66).
        LUGAR="--geometry=${JANELA_LARG}x${JANELA_ALT}+$1+$2"
    else
        LUGAR="--center"          # sem Dock visivel, volta ao meio da tela
    fi

    yad --notebook --key=$YAD_KEY \
        --tab="Aplicativos" \
        --tab="Jogos" \
        --fixed \
        $LUGAR \
        --title="Aplicativos Instalados" \
        --width=$JANELA_LARG --height=$JANELA_ALT \
        --button="Executar:0" \
        --button="Desinstalar:2" \
        --button="Gerenciar Dock:5" 2>/dev/null
    yad_rc=$?
    kill $plug_apps $plug_jogos 2>/dev/null

    case $yad_rc in
        5) # Gerenciar Dock - ao fechar, volta para a grade
            if [ -x "$DOCK_MANAGER" ]; then
                "$DOCK_MANAGER" 2>/dev/null
            fi
            continue
            ;;
        0|2) # Executar/Desinstalar - precisam de um app escolhido
            ;;
        *) # X ou Esc - unico jeito de sair
            exit 0
            ;;
    esac

    if [ ! -s "$SELECTION_FILE" ]; then
        yad --info --center --fixed --title="Escolha um aplicativo" \
            --text="Toque primeiro em um aplicativo da lista\ne depois no botão desejado." \
            --timeout=3
        continue
    fi

    # Identifica o app escolhido a partir do caminho gravado
    desktop_path="$(cat "$SELECTION_FILE")"
    app_name=""
    for key in "${!todos_apps[@]}"; do
        if [ "${todos_apps[$key]}" == "$desktop_path" ]; then
            app_name="$key"
            break
        fi
    done
    if [ -z "$app_name" ]; then
        yad --warning --center --fixed --title="Erro" \
            --text="Aplicativo não encontrado." \
            --timeout=2
        continue
    fi

    if [ "$yad_rc" = "0" ]; then
        # Executar - sem "exec": assim o trap ainda limpa o TMP_DIR
        gio launch "${todos_apps[$app_name]}" >/dev/null 2>&1 &
        disown
        exit 0
    fi

    # Desinstalar (a janela reabre em seguida, sem o app se confirmado)
    uninstall_app "$app_name"
done
