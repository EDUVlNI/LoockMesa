# Loock Mesa 0.20 — galeria e aparência

- Galeria sem barra de título, posicionada na parte inferior do monitor, com entrada e saída suaves e respeito a Reduzir Movimento.
- Busca, categorias, prévias P/M/G e modelos separados. Arraste uma prévia até a Mesa para adicionar ou substituir o widget da categoria. O painel retorna após concluir ou cancelar o arraste. Escape encerra a edição.
- Encaixe indicado durante o arraste; reorganização dos widgets existentes. Uma instância por categoria, como nas versões anteriores.
- Original, Fosco e Transparente, globalmente ou por widget, com intensidade. O Transparente usa tonalidade azul comum e conteúdo dessaturado. A composição nativa do material acompanha o fundo; não captura nem extrai a cor do wallpaper. Reduzir Transparência usa fundo sólido.
- Relógios quadrados analógico e digital; opção de calendário com data grande, além do calendário mensal.
- Anel amarelo quando o Mac ativa Pouca Energia. Com apenas a bateria do Mac no tamanho P, exibe um anel e a porcentagem. O relógio analógico reduz atualizações e omite segundos nesse modo.
- Categoria Tempo de Uso com estado explícito de indisponibilidade. Não importa dados do sistema nem mostra números simulados. A API ScreenTime para macOS documentada pela Apple trata de uso web e não fornece o relatório geral necessário: https://developer.apple.com/documentation/screentime

## Testar

1. Encerre a versão anterior e abra o novo app. As preferências são mantidas.
2. Arraste as prévias P/M/G para a Mesa; teste Escape durante um arraste e posições próximas dos limites da tela.
3. Arraste os dois modelos de relógio e os dois modelos de calendário para substituí-los.
4. Em Ajustes gerais, escolha Transparente. Selecione uma categoria e expanda Personalizar para definir uma exceção individual.
5. Ative Pouca Energia nos Ajustes do Sistema e verifique o anel amarelo da bateria do Mac.

Compilação e testes automatizados não comprovam a experiência de arraste do WindowServer, transições entre monitores, desbloqueio ou composição do wallpaper. Esses pontos precisam de validação na sessão gráfica real.

Ponto de restauração anterior às alterações: tag Git `checkpoint-before-gallery-020` no checkout de desenvolvimento. As preferências permanecem na chave v4; os campos novos são opcionais para permitir migração das versões anteriores.
