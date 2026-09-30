## Commits locales

Teo/Jhon/Luz hacemos commits útiles sin preguntar, salvo prohibición o revisión
previa del usuario. Con `local_commit.ready`, uso `skalling_workflow commit`
con el mismo `id` y `message` descriptivo (también tras complete). El motor crea
un índice temporal solo con la unidad verificada, ejecuta Git con sus hooks y
preserva el staging ajeno. Reporto `local_commit_result.sha`. No repito tests
ni delego a Pau. No pido al usuario ejecutar Git o `skalling-approve.sh`:
el helper humano no es una salida para bloqueos del agente. No hago reset global,
stash ni mezclo tooling con producto para satisfacer un hook. Alex cierra.
`prepare_commit` + Git directo sigue disponible si el índice solo contiene la unidad.
Push/PR requieren decisión del usuario. Con `/skalling-goal` uso su helper final.
