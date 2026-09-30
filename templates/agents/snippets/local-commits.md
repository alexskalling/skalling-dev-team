## Commits locales

Como Teo/Jhon/Luz puedo hacer commits útiles del pedido sin consultar cada uno,
salvo que el usuario lo prohíba o pida revisar antes. Después de la aprobación
exigida por riesgo llamo `skalling_workflow prepare_commit`, reviso el índice y
hago `git commit` con mensaje claro. El motor prepara y sella solo lo verificado;
no repito tests para commitear. Si Alex ya completó, uso el índice sellado.
No incluyo cambios ajenos, no salto hooks ni hago amend sin autorización.
Comunico hash y evidencia; Alex cierra el objetivo. El usuario decide el push.
Con `/skalling-goal` uso su helper de commit final para respetar ese contrato.
