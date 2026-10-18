# Loock Mesa 0.27

- Fundo e grade do modo de edição desenhados nas dimensões reais de cada monitor, sem margens de layout SwiftUI.
- Fade de entrada e saída com cancelamento seguro ao alternar rapidamente entre edição e modo normal.
- Cores Original/Preto/Branco e fundo Original/Fosco acessíveis diretamente nos ajustes individuais.
- Atalhos de aparência no menu de clique direito de todos os widgets; a bateria antiga do Mac também respeita as escolhas.
- Detecção da Mesa usa aplicativo ativo e metadados das janelas visíveis. Se o aplicativo ativo não tem janela no monitor, restaura as cores sem exigir clique no Finder.
- A verificação complementar ocorre a cada 1,25 segundo apenas com Fosco fora da Mesa habilitado, widgets visíveis e tela acordada. Nenhuma imagem ou título de janela é lido.
- Clima Original continua com cores de dia/noite e condição meteorológica.

Validação: build Intel/macOS 13, testes da política de foco, persistência, arrasto e animações. Gestos de Mostrar Mesa, monitores e fade de janela exigem confirmação em sessão gráfica real.
