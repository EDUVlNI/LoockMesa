# Estado desta atualização — 0.30.1

Implementação preparada sobre `EDUVlNI/LoockMesa`, commit base `ff9e2623d8e86859d26c76da3939a61429be0afc`.

- Novo widget Música e Letras independente do player Música.
- Ajuste da navegação/rolagem da galeria para o problema de conteúdo desaparecendo nas abas.
- Testes acrescentados para letras, posição de reprodução, migração e botão de letras desativado.
- Arquivos registrados no projeto Xcode; alvo macOS 13 / Intel mantido.
- Verificações locais: referências de arquivos e Sources do Xcode, Info.plist, diff sem erros de whitespace e análise sintática Swift comparada à base passaram. Não são verificação de tipos nem execução dos testes.

Não foi possível compilar ou executar os testes de macOS neste ambiente Linux. A tentativa de criar a branch no GitHub retornou HTTP 403 (Resource not accessible by integration). Nenhuma alteração foi enviada ao repositório; nenhum PR ou build remoto foi criado.

Abra `LoockMesa.xcodeproj` no Xcode e execute o esquema LoockMesa em My Mac. Os comandos de teste estão no README. Consulte CHANGELOG-0.30.md para o roteiro de validação visual e reprodução do bug. Este pacote contém código-fonte, não um aplicativo compilado.

Refinamento 0.30.1: capa pausada sem blur, barra de tempo interativa, feedback de clique e transformação geométrica play/pause, degradê da capa. Análise sintática comparada ao commit anterior sem erros novos; testes de seek escritos, ainda não executados. A imagem recebida não contém diagnóstico do Build Failed.
