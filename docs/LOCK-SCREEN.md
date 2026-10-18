# Tela de bloqueio — implementação 0.36.2

## Evidência e escopo

Não foi verificado código interno do Alcove. O Atoll credita SkyLightWindow para renderização na tela de bloqueio. A implementação usa a sequência pública no repositório MIT de Lakr233/SkyLightWindow, com resolução dinâmica e validação de símbolos/retornos.

Fontes:
- https://github.com/Lakr233/SkyLightWindow (Sources/SkyLightWindow/SkyLightOperator.swift e TopmostWindow.swift)
- https://github.com/Atoll-Labs/Atoll (créditos)
- https://developer.apple.com/documentation/appkit/nswindow/canbecomevisiblewithoutlogin

## Arquitetura

1. Painéis pequenos e não ativáveis, sem foco de teclado. Informação acima do avatar e player abaixo da autenticação, em coordenadas adaptadas ao Ventura.
2. `canBecomeVisibleWithoutLogin` e nível de janela `Int32.max - 2`, conforme referência MIT.
3. Space privado SkyLight com nível absoluto 400. Adoção dos painéis antes de ordenar suas janelas.
4. Notificações de bloqueio/desbloqueio como sinais; leitura do estado da sessão como confirmação. O dicionário CGSession é público; a chave de bloqueio é não documentada.
5. Remoção imediata ao desbloquear, cancelamento das tarefas de recuperação. Eventos de suspensão ocultam os painéis.
6. Ao bloquear/acordar, recuperação limitada em 0,12 / 0,35 / 0,75 / 1,5 / 3 segundos. Reconciliação de reserva a cada 5 segundos enquanto bloqueado; leitura ociosa a cada 2 segundos.
7. Diagnóstico copiável sem título de música, nome de usuário, conteúdo de senha ou captura de tela. Sucesso da chamada de exibição não prova visibilidade física.

## Limites

API privada, sem garantia de estabilidade entre versões. Não substitui loginwindow, não autentica, não desativa SIP nem usa elevação. Funciona apenas com a sessão e o aplicativo já iniciados. Falhas de símbolos ou chamadas ocultam os painéis. A validação em CI cobre compilação Intel/macOS13, política de sessão, posicionamento e janelas sem foco; exibição e interação na tela realmente bloqueada ainda exigem teste no Ventura do usuário.

## Teste manual

Ativar nas opções gerais; bloquear com Control+Command+Q e observar por pelo menos 10 segundos. Testar play/pause, avanço e letras. Apagar/acordar a tela mantendo o bloqueio. Desbloquear e verificar remoção. Testar senha e Touch ID e troca de usuário. Se falhar, copiar diagnóstico nos ajustes.

## Correção 0.36.3

O diagnóstico no Ventura 13.7.8 mostrou falha na inicialização antes da apresentação. Corrigidos os IDs de Space para UInt64, incluídos aliases CGS, e substituída a interpretação do retorno dos setters privados por leitura independente de nível (400) e associação de cada janela ao Space. Símbolo de destruição é opcional; janelas e Space são ocultados explicitamente no desbloqueio. O diagnóstico agora distingue dlopen, símbolo ausente, conexão, criação e nível lido. Não é possível concluir a causa exata a partir do diagnóstico genérico de 0.36.2.

Referências de assinaturas:
- https://github.com/NUIKit/CGSInternal/blob/master/CGSSpace.h
- https://github.com/asmagill/hs._asm.undocumented.spaces/blob/master/CGSSpace.h

Setters publicados nesses headers usam void, ao contrário das declarações usadas no exemplo SkyLightWindow. A leitura independente evita usar um retorno indefinido como condição para abortar.
