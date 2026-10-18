# Loock Mesa 0.26

- Clima Original preserva as cores de dia/noite e condição meteorológica, mesmo com cores gerais em Preto ou Branco; estilos individuais continuam disponíveis.
- Galeria carrega as categorias sob demanda com LazyVStack.
- Prévias dos relógios deixam de atualizar a cada segundo; materiais de prévia são simplificados para reduzir o número de backdrops nativos.
- Fechar a galeria libera suas prévias e observadores. Reabrir reconstrói o conteúdo e restaura explicitamente a janela e sua opacidade.
- Removida a disputa entre animações de posição ao fechar e reabrir o painel.
- Atualizações de clima, Bluetooth e agenda deixam de invalidar todos os tipos de widgets.
- Serviços pausam quando widgets e galeria estão ocultos, além da suspensão já existente durante repouso do Mac/tela.
- Sair da Mesa mistura o fundo fosco e suaviza as cores por 0,55 segundo, sem disparar o blur e zoom de mudança manual de estilo.

Validação: compilação Release Intel/Ventura e testes de persistência, arrasto, música e animação. Fluidez e consumo de CPU/GPU precisam de validação em uma sessão gráfica real; os testes não substituem uma medição no Mac em uso.
