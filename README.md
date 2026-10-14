# Galaxy Buds para Omarchy

Plugin personal para la barra de Omarchy que muestra mis Galaxy Buds4 Pro: batería de cada auricular y del estuche, si están puestos, el modo de escucha (desactivado, ambiente o ANC), el nivel de ambiente y algunas acciones (detección de conversación, bloqueo táctil, buscar).

```
Buds ─► GalaxyBudsClient ─D-Bus─► bin/galaxybuds-bridge ─► ~/.local/state/galaxybuds/status.json ─► Panel.qml
```

## Restaurar en una instalación nueva

1. Clonar este repo en `~/.config/omarchy/plugins/ajhh.galaxybuds`.
2. Ejecutar `./setup`. Instala `galaxybudsclient-bin` del AUR, activa los servicios de usuario y el plugin.
3. Abrir GalaxyBudsClient una vez y elegir los Buds en el asistente.

Con eso funciona todo menos el modo de escucha y el nivel de ambiente, que necesitan la versión parcheada de GalaxyBudsClient (paso siguiente).

## Versión parcheada de GalaxyBudsClient

Mientras no se publiquen mis PRs en una versión oficial ([#751](https://github.com/timschneeb/GalaxyBudsClient/pull/751), [#752](https://github.com/timschneeb/GalaxyBudsClient/pull/752), [#753](https://github.com/timschneeb/GalaxyBudsClient/pull/753)), uso una compilación propia:

```bash
git clone https://github.com/AJHH24/GalaxyBudsClient ~/Work/GalaxyBudsClient
cd ~/Work/GalaxyBudsClient
git switch feat/ipc-noise-control-v2
git merge origin/fix/ipc-strip-nul-strings origin/fix/linux-bluez-watcher-leak

# SDK que pide global.json, sin sudo
curl -fsSL https://dot.net/v1/dotnet-install.sh | bash -s -- --jsonfile global.json --install-dir ~/.dotnet
export DOTNET_ROOT=~/.dotnet PATH=~/.dotnet:$PATH

dotnet publish GalaxyBudsClient/GalaxyBudsClient.csproj -c Release -r linux-x64 \
  --self-contained -p:PublishSingleFile=true -o ~/.local/opt/galaxybudsclient-ipc

# Que el servicio y el lanzador usen esa versión
mkdir -p ~/.config/systemd/user/galaxybudsclient.service.d
cp extras/ipc-noise-control.conf ~/.config/systemd/user/galaxybudsclient.service.d/
cp extras/galaxybudsclient.desktop ~/.local/share/applications/
systemctl --user daemon-reload && systemctl --user restart galaxybudsclient
```

Cuando los PRs lleguen al AUR, borrar esos dos archivos, ejecutar `systemctl --user daemon-reload` y volver al paquete oficial.

## Notas

- GalaxyBudsClient se rinde si los Buds estaban apagados cuando arrancó y no vuelve a intentarlo. El puente lo cubre: cuando BlueZ conecta los Buds (dirección guardada en `~/.local/state/galaxybuds/address`) y la app sigue sin ellos tras 4 s, le manda la acción `Connect`.
- Si el plugin deja de cargar tras editarlo, ejecutar `omarchy restart shell`: la recarga en caliente conserva el QML viejo después de un error.
- IPC: `omarchy-shell galaxybuds off|ambient|anc|cycle|mode|battery` y `omarchy-shell galaxybuds ambientLevel 1..5`.
