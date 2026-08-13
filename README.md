# tarsila-app-management

Gerenciador de aplicativos nativo do **Tarsila OS** — pacote Debian separado.

## O que faz

- **Instalar** `.deb` com duplo clique (janela GTK com barra de progresso)
- **Desinstalar** com botão direito nos ícones da dock
- **Gerenciar** aplicativos visualmente (lista, busca, lança, desinstala)

## Componentes

| Arquivo | Função |
|---|---|
| `tarsila-deb-gui.py` | Instalador gráfico de `.deb` (GTK3) |
| `tarsila-deb-instalar` | Backend do instalador (roda como root via `sudo -S`) |
| `tarsila-app-uninstall.sh` | Desinstalador (Desktop Action dos atalhos curados) |
| `tarsila-appfinder-yad.sh` | Gerenciador visual de apps (YAD) |
| `tarsila-deb-installer.desktop` | Handler MIME para `.deb` |
| `tarsila-appfinder-yad.desktop` | Launcher do AppFinder |

## Dependência com a Tarsila Store

Este pacote funciona **sem** a Tarsila Store. Se a Store estiver instalada
(`/opt/tarsila-store/bin/tarsila-pkg` existe), os desinstaladores delegam
para ela — preservando a whitelist do catálogo comunitário. Se não, usam
`apt-get remove` direto.

A Tarsila Store, por sua vez, **depende** deste pacote (`Depends:
tarsila-app-management`).

## Build

```bash
./build-deb.sh [versão]   # padrão: 1.0.0
```

Gera `tarsila-app-management_<versão>_all.deb`.

## Dependências (apt)

`python3`, `python3-gi`, `python3-gi-cairo`, `gir1.2-gtk-3.0`, `yad`,
`wmctrl`, `xdotool`, `imagemagick`, `apt`, `sudo` (Recommends: `libnotify-bin`).
