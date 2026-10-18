# Loock Mesa 0.29

- Corrigido o relógio parado: o desenho e a hora digital agora recebem a hora real por um temporizador em modos comuns do RunLoop, sem depender de callbacks do TimelineView em painéis da Mesa.
- Um temporizador por relógio visível, alinhado ao segundo real. Reconfigurar o widget não cria temporizadores duplicados.
- O analógico para fora da Mesa quando o efeito está habilitado e recupera a posição correta ao voltar. As animações de ponteiros e marcadores permanecem funcionando.
- Ciclo de vida ligado à janela AppKit: alterações de foco, remoção e reabertura atualizam o relógio mesmo quando callbacks SwiftUI são suspensos.
- O digital atualiza os minutos e os marcadores de segundos pela mesma fonte de tempo.
- Prévias da galeria permanecem sem temporizadores. Relógios ocultos e durante repouso da tela/Mac também suspendem atualizações.
- Economia de energia mantém a hora correta a cada segundo, simplificando a animação normal e reduzindo os frames durante a recuperação.
- Geometria dos 60 marcadores calculada uma vez por tamanho. Fontes digitais reutilizadas em cache.

Validação: compilação Release x86_64/macOS 13, testes de temporizador real, pausa/repouso, recuperação/cancelamento, ausência de duplicação e imagens sucessivas do NSHostingView para verificar movimento, congelamento e retorno. Comportamento durante gestos de Mostrar Mesa e consumo no Mac do usuário precisam de confirmação em sessão gráfica real.
