# LoockMesa 0.31.0 — implementação, ainda sem build macOS

## Alterações

- Barra do widget Música e Letras: 2 pt em repouso, 6 pt ao aproximar o cursor ou arrastar; transição de 0,2 s. Área de proximidade maior que a linha, com estado individual por widget. A superfície nativa de seek continua interceptando o arraste para não mover o widget.
- Gradiente compartilhado pelos dois widgets: cor da capa, complementar e variação próxima, em três posições sorteadas por faixa. A posição não muda com as notificações de reprodução nem com a chegada tardia da capa. Tema claro/escuro e transparência mantidos.
- Música e Letras passa a usar o mesmo flip 3D da capa do player Música. Troca da imagem no meio do giro. Reinício seguro ao interromper o giro com outra faixa; preferência Reduzir Movimento interrompe o giro.
- Cancelamento do seek pendente ao remover o controle da janela.
- Versão 0.31.0 (33). Script `scripts/build-app.sh` gera build Release Intel/macOS 13 e ZIP com `.app` assinado ad hoc. Workflow macOS executa testes e disponibiliza esse ZIP como artefato, se passar.

## Verificação realizada

Comparação sintática de todos os fontes Swift com o commit anterior usando tree-sitter: sem novos erros. Info.plist válido. Script validado com `bash -n`; `git diff --check` sem erros. A revisão não substitui compilação/verificação de tipos.

## Bloqueio de entrega

Ambiente atual Linux, sem SDK macOS/Xcode. O script interrompe corretamente nesse ambiente. As tentativas de escrita no GitHub nesta sessão retornaram 403 (Resource not accessible by integration), impedindo enviar a branch e iniciar o build macOS. Não foi gerado nem executado um `.app` desta versão. O comportamento visual e a correção completa do bug de galeria ainda exigem teste num Mac.

## Validação necessária antes de considerar versão final

No macOS, executar os três scripts de Tests e `bash scripts/build-app.sh`. Verificar troca rápida de faixas, capa chegando atrasada, pausa, hover em vários widgets independentes, seek com mudança de faixa e remoção do widget, Reduzir Movimento, navegação repetida pelas abas e abertura do aplicativo extraído fora do Xcode. O pacote é assinado ad hoc, sem notarização Apple.
