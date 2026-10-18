# Loock Mesa 0.28

- Fosco fora da Mesa mantém o conteúdo opaco e apenas suaviza levemente sua saturação. Intensidade do material limitada para manter legibilidade e cor do wallpaper.
- Ponteiro de segundos e centro laranja visíveis em todos os estilos, inclusive economia de energia (com frequência reduzida de atualização).
- Analógico congela os ponteiros fora da Mesa quando o efeito está habilitado. Ao voltar, recupera a posição correta no sentido horário em 0,7 segundo, com cancelamento ao sair novamente e respeito a Reduzir Movimento.
- Números analógicos em SF Pro Rounded Medium, com proporção e alinhamento revistos. Digital usa SF Pro do sistema com alternativas tipográficas, sem incluir arquivos de fontes Apple no pacote.
- Marcadores dos dois relógios acompanham o contorno arredondado com 7 pontos de respiro. O marcador ativo alonga e ganha contraste ao avançar o segundo.
- Fade da grade calculado diretamente na opacidade da janela ao longo de 0,32 segundo, preservando a opacidade atual ao inverter a transição.

Fontes oficiais: https://developer.apple.com/fonts/ e https://developer.apple.com/documentation/technologyoverviews/fonts

Validação: build Release Intel/Ventura, testes de pausa e recuperação/cancelamento, migração/persistência e renderização da tipografia. Fade de janelas e comportamento durante gestos de Mostrar Mesa ainda exigem validação na sessão gráfica do usuário.
