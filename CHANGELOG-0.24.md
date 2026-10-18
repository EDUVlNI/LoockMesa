# Loock Mesa 0.24

- Tempo de Uso removido da galeria, da Mesa e das preferências salvas.
- Superfície Transparente e efeito global preto e branco removidos; layouts antigos migram automaticamente para Fosco e cores normais.
- Personalização reduzida a Original/Fosco e aos estilos Original/Branco/Preto.
- Mudanças de aparência recebem uma transição curta com blur, opacidade e escala, respeitando Reduzir Movimento.
- Nova opção “Fosco fora da Mesa”: ao ativar outro app, os widgets recebem material translúcido e saturação parcial, sem preto e branco.
- Relógio digital refinado com SF Pro Condensed Heavy menos deformada, tracking mais natural e proporções independentes para P/M.

Validação: build Release x86_64 para macOS Ventura, migração de preferências, testes de interação e renderização visual. A detecção “fora da Mesa” usa o aplicativo ativo: Finder e Loock são tratados como Mesa.
