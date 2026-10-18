# Loock Mesa 0.25

- Corrigido o modo “Fosco fora da Mesa”: o material agora fica atrás do conteúdo, sem transformar os widgets em blocos vazios.
- O efeito fora da Mesa preserva as cores com saturação e opacidade suaves, sem aplicar preto e branco.
- Aparência individual por widget com as opções Original, Branco e Preto.
- Superfície individual por widget com as opções Original e Fosco.
- Widget de Clima compatível com Fosco, Branco e Preto, mantendo contraste nos textos, divisores e ícones meteorológicos.
- Números do relógio analógico ajustados para a variante arredondada em peso Bold.
- Preferências antigas continuam sendo migradas automaticamente; Tempo de Uso e Transparente permanecem removidos.

Validação: build Release x86_64 para macOS Ventura, testes de persistência e migração, testes de arrastar e animação, além de renderização visual dos estilos foscos.
