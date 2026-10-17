# Loock Mesa 0.30

- Nova categoria **Música e Letras**, independente do widget Música, com tamanhos P/M/G e aparência própria. Layouts anteriores ganham a nova categoria desativada, preservando Música e suas posições.
- Player com capa, título, artista, progresso, anterior, reproduzir/pausar e próxima. Balão no canto superior direito alterna letras; sem letra, permanece escuro e desativado, inclusive no controle nativo da Mesa.
- Busca exata no LRCLIB por faixa, artista, álbum e duração. Cache em memória limitado a 32 faixas, cancelamento e proteção contra respostas atrasadas. Erros transitórios podem ser tentados novamente após 60 segundos. A consulta só é ativada quando o novo widget está na Mesa.
- Letras sincronizadas por linha usando posição/timestamp do player. Letras sem marcação de tempo permitem rolagem manual. Sem posição informada pelo player, não é simulada sincronização.
- Transições curtas entre modos, deslocamento suave das letras e mudança gradual de cor. Respeita Reduzir Movimento.
- Galeria: cada aba recria sua área de rolagem; catálogo sem virtualização e categoria explícita independente do filtro global evitam conteúdo fora da área visível ao alternar abas.

## Validação necessária no Mac

A correção da galeria trata o reaproveitamento de rolagem/layout; o bug intermitente relatado precisa de confirmação em uso real. Percorrer Todos até o fim, abrir todas as categorias e Ajustes gerais, pesquisar/limpar e repetir após fechar/reabrir a galeria.

Testar Spotify e Apple Music: tocar, pausar, buscar na faixa, mudar rapidamente de música, faixa instrumental, letra indisponível, rede offline e retorno. Verificar P/M/G, aparência clara/escura, arrasto, modo de edição e Reduzir Movimento no Ventura 13.7. O MediaRemote continua privado e experimental.

## 0.30.1 — refinamento visual e interação

- Remove o blur aplicado à capa do widget Música ao pausar.
- Barra de tempo interativa no Música e Letras: clique, arrasto com prévia, comando ao soltar e setas do teclado em passos de cinco segundos. Trocar de música cancela o arrasto anterior. A área da barra não arrasta o widget.
- Feedback de clique: pequeno deslocamento direcional nos botões anterior/próxima, escala discreta e brilho curto. Play/pause usa interpolação geométrica compatível com Ventura, também no widget Música.
- Aparência Original do Música e Letras usa degradê baseado em três regiões da capa, com transição de cor. Não há animação contínua decorativa.
- Os testes de seek foram adicionados, mas não executados: continua necessária compilação e validação no Mac. A captura enviada mostra o widget, não a mensagem do erro anterior de build.
