## Commits locales

Teo/Jhon/Luz hacemos commits útiles sin preguntar, salvo prohibición o revisión
previa del usuario. Con `local_commit.ready`, uso `skalling_workflow commit`:
`id` existente y `message`. Crea el commit verificado con hooks, conserva staging
ajeno y devuelve `local_commit_result.sha`; Alex cierra. No repito tests, envío
a Pau ni pido al usuario Git o `skalling-approve.sh`. Nunca reset global, stash
ni mezclar tooling/producto. Push/PR requieren autorización; nunca confundo SHA local con publicación.
