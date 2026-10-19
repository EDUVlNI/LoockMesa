# Gergelim

Aplicativo para macOS Ventura 13+ Intel que reúne os widgets do LoockMesa 0.38.1 e o Eko 2.2.

- Widgets e editor da Mesa preservados.
- Capsule de informações (sem player interno), indicadores reordenáveis, Siri e fones.
- HUDs de volume, brilho de tela/teclado, Touch Bar e cantos de tela.
- Player flutuante original do Eko usando o mesmo serviço musical dos widgets.
- Configurações em uma única janela; ícone de semente na barra de menus.
- Importa preferências dos dois aplicativos uma vez para seu próprio identificador `com.eduvini.Gergelim`.

Encerre Eko e LoockMesa antes de usar Gergelim, para evitar HUDs e widgets duplicados.
Acessibilidade e outras permissões precisam ser concedidas ao novo aplicativo.
O modo experimental da Touch Bar e seu watchdog são preservados do Eko.

A imagem definitiva do aplicativo será adicionada quando fornecida. O ícone provisório usa uma semente.

## Origem

Eko: EDUVlNI/ekoapp, main e959434 (2.2).
LoockMesa: EDUVlNI/LoockMesa, fa96fae (0.38.1).

## Compilar

`bash scripts/build-app.sh` em macOS com Xcode. Saída: `dist/Gergelim-1.0-Intel.zip`.
