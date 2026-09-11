# Bitácora de desarrollo — excel-processing-pipeline-gke

Registro cronológico de las decisiones tomadas durante el desarrollo del
proyecto: qué se decidió, por qué, qué alternativas se descartaron y qué
problemas aparecieron en el camino. La idea es poder reconstruir el
razonamiento después, o no repetir un problema ya resuelto.

Escrita en español por ahora — se traduce a inglés más adelante.

---

## 1. Definición del proyecto y arquitectura

Se definió el propósito y la arquitectura del proyecto: un pipeline de
procesamiento asíncrono de archivos Excel sobre GCP.

Arquitectura acordada:

- API en FastAPI sobre Cloud Run, sube archivos a GCS y guarda estado en
  Firestore (`job_id` como ID de documento).
- GCS notifica nativamente a Pub/Sub (`OBJECT_FINALIZE`) — la API nunca
  publica el mensaje manualmente, para evitar el problema de dual-write.
- Worker en GKE consume el mensaje, procesa el archivo, actualiza estado.
- Autenticación de llamadas a la API vía Service Account + IAM
  (`roles/run.invoker`), sin base de datos de usuarios propia.
- Infra gestionada con HCP Terraform, autenticación a GCP vía Workload
  Identity Federation (sin keys estáticas).
- Dev y prod como proyectos de GCP completamente separados, cada uno bajo su
  propio Folder dentro de una Organization (Cloud Identity Free).
- Permisos de IAM otorgados a grupos de Cloud Identity, nunca a Service
  Accounts individuales.
- Región: europe-west9 (Paris).

Se definió también la estructura de carpetas del repo (`api/`, `processor/`,
`configs/`, `cloudbuild/`, `docs/`, `terraform/{modules,domains,platform}/`) y
la convención de nombres de recursos GCP (`{proyecto-corto}-{componente}-
{entorno}`, con `excel-pipeline` como nombre corto para no exceder el límite
de 30 caracteres de un Project ID de GCP).

## 2. Scaffolding inicial

- Se creó `.gitignore` cubriendo Terraform (`.tfstate`, `.terraform/`,
  `.tfvars`), credenciales de GCP (por nombre de archivo, sin bloquear todo
  `*.json` porque `firestore.indexes.json` debe versionarse), entornos
  Python, Kustomize, editores/SO.
- Se crearon los directorios `dev/` y `prod/` dentro de cada domain en
  `terraform/domains/` (`cloud-run`, `data`, `gke`, `networking`), cada uno
  con `main.tf`, `variables.tf`, `outputs.tf`.
- Se definió la convención: el bloque `terraform {}` de cada configuración va
  en un archivo separado llamado `terraform.tf` (no `versions.tf`), en todo
  el repo. Se agregó ese archivo a los 8 directorios domain×entorno ya
  creados.

## 3. Diseño de `terraform/platform/hcp/`

Este directorio gestiona la Organización, Proyectos y Workspaces de HCP
Terraform (distinto de los "Project" de GCP).

**Convención de nombres de HCP Terraform**:

| Concepto | Patrón | Ejemplo |
|---|---|---|
| HCP Terraform Project (agrupa workspaces) | `excel-processing-pipeline-gke-{dev\|prod\|mgmt}` (nombre completo, sin el límite de 30 caracteres de GCP) | `excel-processing-pipeline-gke-dev` |
| Workspace de dominio | `excel-pipeline-{domain}-{dev\|prod}` (único a nivel organización) | `excel-pipeline-networking-dev` |
| Workspace del proyecto mgmt | `excel-pipeline-{hcp\|governance}-mgmt` | `excel-pipeline-hcp-mgmt` |

**Estructura de archivos propuesta** para `platform/hcp/`: `terraform.tf`,
`providers.tf`, `organization.tf`, `projects.tf`, `locals.tf`,
`workspaces.tf`, `variable_sets.tf`, `variables.tf`, `outputs.tf` — separando
por tipo de recurso para claridad.

## 4. El problema de bootstrap (huevo y gallina)

Pregunta: si `platform/hcp` es el código que crea los workspaces de HCP
Terraform, ¿quién aplica ese código la primera vez, si el workspace que
debería aplicarlo todavía no existe?

**Decisión:** crear a mano (fuera de Terraform) una organización, un
proyecto `excel-processing-pipeline-gke-mgmt` y una workspace
`excel-pipeline-hcp-mgmt` dentro de ese proyecto. Ese workspace aplica
`platform/hcp/`, que a su vez crea los proyectos `-dev`/`-prod` y sus 8
workspaces de dominio.

**Decisión relacionada:** el proyecto y la workspace de mgmt **no se
importan** al state de Terraform — quedan deliberadamente fuera de gestión
por código, para evitar que una workspace pueda auto-destruirse (el
"self-management footgun": si se importaran, un `destroy` accidental podría
borrar la workspace que está corriendo ese mismo apply).

Configuración manual de la workspace `excel-pipeline-hcp-mgmt`:
- Working directory: `terraform/platform/hcp`.
- VCS trigger pattern: `terraform/platform/hcp/**` (solo dispara plan si
  cambian archivos ahí).
- Sin auto-apply (manual apply), por ser la workspace más sensible (puede
  crear/borrar otras workspaces y proyectos).

## 5. Autenticación de la workspace de mgmt contra la API de HCP Terraform

Esta workspace corre el provider `tfe`, así que necesita autenticarse contra
la API de HCP Terraform — algo distinto de la autenticación a GCP (que usa
WIF).

Opciones consideradas:
- **`terraform login`**: descartada — es para autenticar el CLI local de un
  humano (flujo interactivo con browser), no aplica a una workspace que
  corre remota.
- **User Token**: descartado — atado a una identidad personal, no auditable
  como acción de la automatización.
- **Organization Token**: descartado — privilegio casi-owner sobre toda la
  organización, más de lo necesario.
- **Team API Token** (elegido): sigue el mismo patrón de RBAC que el resto
  del proyecto (permisos a un team, no a una identidad individual).

**Problema encontrado:** el free tier de HCP Terraform no permite crear
teams custom — solo existe el team `owners`. Ya lo habían reportado otros
usuarios.

**Resolución:** usar el Team API Token del team `owners` como excepción
documentada, dejando anotado que en un tier pago correspondería crear un team
dedicado con permisos mínimos.

**Nota:** ese team (`owners`) no se puede crear vía Terraform desde la propia
workspace que lo necesita para autenticarse — mismo problema de bootstrap que
el punto 4, así que también se gestiona a mano.

## 6. Código de `projects.tf`, `locals.tf`, `workspaces.tf`

Se escribió el patrón para crear los 2 proyectos (dev/prod) y sus 8
workspaces de dominio sin repetir bloques de recurso a mano:

- `locals.tf`: `local.workspaces` construido con `setproduct(keys(local.
  projects), local.domains)` — producto cartesiano de entornos × domains,
  transformado en un mapa vía un *for expression*, con la clave
  `"{domain}-{entorno}"` y como valor un objeto con `environment`, `domain`,
  `project_id` y `working_directory`.
- `workspaces.tf`: un único `resource "tfe_workspace" "domain"` con
  `for_each = local.workspaces`, `auto_apply = false`, y
  `trigger_patterns` acotado a la carpeta del domain más
  `terraform/modules/**` (para que cambios a módulos compartidos también
  disparen el plan correspondiente).

## 7. Variables sensibles: qué es sensible y qué no

- `vcs_repo_identifier` (`owner/repo`): no sensible, es información pública.
- IDs de conexión VCS: se discutió si marcarlos `sensitive = true`. Conclusión:
  no son secretos en sí (son solo IDs de referencia, el secreto real vive del
  lado de HCP Terraform), pero se marcan igual como higiene defensiva.
- Se reforzó dos veces la regla: el *key* de una variable cargada en la UI de
  HCP Terraform tiene que matchear **exactamente** el nombre del bloque
  `variable` del código (case-sensitive), y tiene que cargarse como
  categoría **Terraform Variable**, no **Environment Variable** — son dos
  mecanismos distintos y no son intercambiables.

## 8. El problema de la conexión VCS (GitHub App) — varios intentos fallidos

Se conectó inicialmente el repo a la workspace de mgmt vía **GitHub App**
(el método recomendado por HashiCorp). Esto llevó a varios problemas
encadenados:

1. **Scope de proyecto:** la conexión GitHub App se había cargado a nivel del
   proyecto `mgmt` únicamente, no a nivel organización — lo cual iba a hacer
   fallar la creación de los 8 workspaces de dominio, que viven en los
   proyectos `dev`/`prod` (proyectos distintos, sin acceso a esa conexión).
2. **Intento de arreglar el scope:** se intentó reinstalar/desinstalar la
   GitHub App (tanto desde HCP Terraform como desde GitHub) para poder
   cambiar el scope a "todos los proyectos". La UI de HCP Terraform quedó en
   un estado inconsistente — seguía mostrando la conexión como `installed`
   incluso después de desinstalar la app del lado de GitHub, sin ofrecer
   forma de editarla ni borrarla desde la UI (probablemente un bug o un
   estado cacheado del lado de HCP Terraform).
3. **Confusión de tokens:** se encontró en HCP Terraform (User Settings →
   Tokens) un "GitHub App OAuth Token" generable, que se pensó podía servir
   para destrabar el problema. Se aclaró que es un token personal (uno por
   usuario, vincula la identidad de GitHub con la GitHub App ya instalada) —
   no es el mismo objeto que necesita el código (`github_app_installation_id`
   o un Personal Access Token clásico), y no resolvió el problema de scope.

**Decisión final:** abandonar el método GitHub App y usar en su lugar el
recurso `tfe_oauth_client` (conexión OAuth clásica), con:
- `oauth_token`: un Personal Access Token (classic, scope `repo`) generado
  directamente en GitHub (Settings → Developer settings → Personal access
  tokens) — **no** el "GitHub App OAuth Token" de HCP Terraform, que es un
  objeto distinto y no compatible con este recurso.
- `organization_scoped = true`: resuelve el problema de scope de forma
  declarativa, sin depender de configurarlo a mano en la UI.

Este cambio esquiva por completo el estado roto de la GitHub App — es un
mecanismo de conexión totalmente independiente.

## 9. Dónde vive el token — se descartó un variable set

Se consideró (y se descartó) cargar el `github_oauth_token` en un variable
set a nivel organización. Razones:
- Solo lo consume una workspace (`excel-pipeline-hcp-mgmt`) — un variable set
  tiene sentido cuando varias workspaces necesitan el mismo valor, no es el
  caso acá.
- Es un secreto real (a diferencia de los IDs de conexión) — un variable set
  a nivel organización lo propagaría a las 8 workspaces de dominio también,
  aunque ninguna lo necesite, ampliando sin motivo la superficie de
  exposición. Va en contra del mismo principio de mínimo privilegio aplicado
  a los grupos de IAM de GCP.

**Decisión:** cargarlo directo como Terraform Variable sensible en la
workspace `excel-pipeline-hcp-mgmt` únicamente.

Las workspaces de dominio (dev/prod) no necesitan el token en ningún momento:
su conexión VCS (`vcs_repo`) queda pre-configurada como atributo del objeto
workspace cuando `mgmt` las crea — no es algo que ellas lean en sus propios
runs.

## 10. Regla de idioma en el código

Se estableció que todo el código (`.tf`, comentarios, `description` de
variables/outputs, y en el futuro código de `api/`/`processor/`) se escribe
en **inglés**. La documentación de proceso, como esta bitácora, queda en
español por ahora.

## 11. Cómo llegan las variables a un workspace VCS-driven

Surgió la duda de cómo evitar repetir `-var`/`-var-file` en cada plan/apply,
y cómo pasar variables si el workflow es VCS-driven.

**Aclaración conceptual:** `-var`/`-var-file` son flags de una invocación
manual del CLI — no existen como concepto en un workspace VCS-driven, porque
ahí nunca se corre `terraform` a mano; un push dispara el run automáticamente.
Lo que sí ocurre en cada run remoto es que HCP Terraform arma el entorno de
ejecución leyendo automáticamente todas las Terraform Variables y Environment
Variables asociadas a esa workspace — las cargadas directo, más las heredadas
de cualquier Variable Set attacheado a la workspace o a su proyecto. Es un
mecanismo de "cargar una vez, se propaga solo en cada run futuro", no algo
que se repita manualmente.

Aplicado a las credenciales WIF de GCP: un `tfe_variable_set` por proyecto
(uno para dev, otro para prod), attacheado al proyecto entero vía
`tfe_project_variable_set` — así las 4 workspaces de dominio de cada entorno
heredan las mismas credenciales sin configurarlas una por una, y cualquier
workspace nueva que se agregue a ese proyecto las hereda automáticamente.

**Punto que generó confusión:** los valores reales que van dentro de esas
`tfe_variable` (project number, workload provider ID, etc.) necesitan
proveerse igual la primera vez — pero no vía `-var`, sino como Terraform
Variables cargadas a mano, una sola vez, en la propia workspace
`excel-pipeline-hcp-mgmt` (la que ejecuta el código que crea esos variable
sets). De ahí en más, quedan persistidas del lado de HCP Terraform y se
propagan solas a cada workspace de dominio en cada run futuro.

## 12. Variables de dynamic credentials para GCP — verificación

Se verificó contra la documentación oficial de HashiCorp la lista completa de
variables de entorno necesarias para dynamic credentials con el provider de
GCP (había una faltante en lo discutido hasta ese momento):

| Variable | Valor |
|---|---|
| `TFC_GCP_PROVIDER_AUTH` | `"true"` |
| `TFC_GCP_PRINCIPAL_TYPE` | `"service_account"` |
| `TFC_GCP_PROJECT_NUMBER` | project number (no el project ID) donde vive el pool |
| `TFC_GCP_WORKLOAD_POOL_ID` | ID del workload identity pool |
| `TFC_GCP_WORKLOAD_PROVIDER_ID` | ID del provider dentro del pool |
| `TFC_GCP_RUN_SERVICE_ACCOUNT_EMAIL` | email de la Service Account a impersonar |

Todas van como categoría **Environment Variable** (las lee el provider
`google` directo del entorno del proceso, no vía `var.x`).

## 13. El problema de bootstrap de GCP (proyecto semilla)

Apareció un tercer caso del mismo patrón de huevo-y-gallina, ahora en la capa
de GCP: para crear los proyectos dev/prod y la organización con Terraform sin
usar keys estáticas, hace falta WIF — pero el pool/provider de WIF vive
*dentro de un proyecto de GCP que ya tiene que existir*, y ese proyecto no
puede ser dev ni prod porque son justamente los que todavía no existen.

**Decisión:** un proyecto semilla/bootstrap de GCP, creado a mano (con
usuario humano, no Terraform), que aloja únicamente:
- El Workload Identity Pool + Provider.
- Una Service Account (ej. `terraform-admin-sa`) que Terraform impersona.

La clave del mecanismo: dónde vive la Service Account (el proyecto semilla)
y qué permisos tiene son cosas separadas. Los permisos reales para crear
folders y proyectos se le otorgan a esa SA con bindings de IAM **a nivel
Organización** (`roles/resourcemanager.folderCreator`,
`roles/resourcemanager.projectCreator`, `roles/billing.user` sobre la cuenta
de facturación) — no a nivel del proyecto semilla. El binding
`roles/iam.workloadIdentityUser` restringe además qué workspace específica
puede impersonar esa SA.

Los pasos de creación del dominio, la Organización (Cloud Identity), el
proyecto semilla, la SA y sus bindings de IAM son manuales — mismo motivo que
en los puntos 4 y 5: no se puede usar WIF para crear la identidad que WIF
necesita para autenticarse. Esto queda bloqueado hasta comprar el dominio.

**Decisión de ubicación:** el código que crea los folders y los proyectos
dev/prod (una vez que el proyecto semilla exista) va a vivir en
`terraform/platform/governance/`, junto con los bindings de IAM a nivel
org/folder — se trató como una sola responsabilidad ("todo lo que es meta a
nivel organización") en vez de separarlo en un directorio aparte.

## 14. Setup inicial del proyecto bootstrap de GCP

Con el dominio comprado, Cloud Identity activada y la Organización ya creada
(prerequisito que había quedado bloqueado en el punto 13), se creó a mano el
folder `bootstrap` con el proyecto semilla (`excel-pipeline-seed`) adentro:
aloja únicamente el Workload Identity Pool/Provider y la Service Account que
Terraform va a impersonar para gestionar el resto de la organización
(folders, proyectos dev/prod/shared). Es un "root of trust" — sostiene
permisos a nivel Organización, así que conviene mantenerlo aislado y de bajo
tráfico para que sea fácil de auditar. No aloja carga de trabajo de la
aplicación.

> En un momento de esta etapa se planeó crear también, en el mismo paso
> manual, un folder `shared` con un proyecto `excel-pipeline-shared` para
> alojar recursos compartidos como Artifact Registry — pero solo se llegó a
> ejecutar la creación del proyecto semilla. Ver punto 21: ese proyecto
> shared se termina creando por código, no a mano.

Pasos ejecutados — variables de entorno con valores de ejemplo, después la
secuencia de comandos:

```bash
# Variables de entorno (valores de ejemplo — reemplazar por los propios)
export ORG_ID="123456789012"
export ADMIN_USER="admin@example.dev"
export BOOTSTRAP_FOLDER_NAME="bootstrap"
export SEED_PROJECT_ID="excel-pipeline-seed"
export REGION="europe-west9"

# Otorgar al usuario administrador permiso para crear folders a nivel
# organización (necesario antes de poder crear el folder)
gcloud organizations add-iam-policy-binding "$ORG_ID" \
  --member="user:$ADMIN_USER" \
  --role="roles/resourcemanager.folderAdmin"

# --- Folder bootstrap + proyecto semilla ---
BOOTSTRAP_FOLDER_NAME_FULL=$(gcloud resource-manager folders create \
  --display-name="$BOOTSTRAP_FOLDER_NAME" \
  --organization="$ORG_ID" \
  --format="value(name)")
BOOTSTRAP_FOLDER_ID="${BOOTSTRAP_FOLDER_NAME_FULL#folders/}"

gcloud projects create "$SEED_PROJECT_ID" \
  --folder="$BOOTSTRAP_FOLDER_ID" \
  --name="excel-pipeline-seed-project" \
  --labels=type=seed-project

# Crear una configuración de gcloud CLI dedicada para el proyecto semilla,
# para no operar accidentalmente sobre otro proyecto/contexto
gcloud config configurations create excel-pipeline-seed
gcloud config set project "$SEED_PROJECT_ID"
gcloud config set compute/region "$REGION"

# Verificar
gcloud config configurations describe excel-pipeline-seed
```

Quedaba pendiente crear, sobre este proyecto, el Workload Identity Pool +
Provider y la Service Account que Terraform va a impersonar — resuelto en
el punto 18.

## 15. Workspace de governance agregada al código de `hcp`

`workspaces.tf` solo tenía el `for_each` de las 8 workspaces de dominio —
faltaba `excel-pipeline-governance-mgmt`, la que va a aplicar
`terraform/platform/governance/`. Se agregó como un recurso `tfe_workspace`
aparte (no dentro del `for_each` de dominios, porque no es un dominio), en
el proyecto mgmt.

Para ubicarla en ese proyecto sin volver a caer en el problema de
auto-gestión del punto 4, se agregó `data "tfe_project" "mgmt"` — lee el
proyecto mgmt (creado a mano) por nombre, sin importarlo al state. No hay
riesgo de auto-destrucción acá porque quien aplica este código
(`hcp-mgmt`) no es el mismo objeto que se está creando (`governance-mgmt`)
— el riesgo de auto-gestión es específico a una workspace pudiendo
gestionarse *a sí misma*, no a que gestione a otras dentro del mismo
proyecto.

## 16. Refactor a creación dinámica de proyectos — bugs encontrados

Se cambió `projects.tf` de dos recursos nombrados (`tfe_project.dev`,
`tfe_project.prod`) a uno solo con `for_each`. El primer intento tenía tres
errores de sintaxis:

1. **Dependencia circular:** `local.projects` se usaba a la vez como
   *input* del `for_each` (qué proyectos crear) y como *output* (un mapa
   construido a partir de esos mismos proyectos ya creados) — Terraform no
   puede resolver eso, es un ciclo. Se resolvió separando los dos
   conceptos: `local.environments = toset(["dev", "prod"])` como input
   estático (no depende de nada), y referencias directas a
   `tfe_project.environments[key].id` donde antes se usaba el local
   circular.
2. **Referencias rotas:** `locals.tf` seguía apuntando a
   `tfe_project.dev`/`.prod`, que ya no existían tras el rename a
   `tfe_project.environments`.
3. **Mal uso de splat con `for_each`:** en `variable_sets.tf`,
   `tfe_project_variable_set` intentaba usar `tfe_project.environments[*].id`
   (splat, válido solo con `count`) para vincular *todos* los proyectos con
   *todos* los variable sets a la vez — pero ese recurso vincula uno a uno.
   Se corrigió agregándole su propio `for_each = local.environments`, para
   que cada entorno se empareje con su propio variable set por clave.

## 17. Quién escribe los valores reales de las variable sets

Al ir a poblar los `tfe_variable` con los valores `TFC_GCP_*` de dev/prod,
surgió la pregunta de cómo traerlos si los proyectos dev/prod (y su WIF
interno) todavía no existen.

**Aclaración de fondo:** no es un problema de "cómo leer el dato" — es que
el dato no existe todavía, y además `hcp` no tiene ningún acceso a GCP (ni
siquiera para un `data` block) porque esa workspace solo habla con la API
de HCP Terraform, por diseño. Ni con `data` ni de ninguna otra forma puede
`hcp` resolver esto.

**División de responsabilidad, entonces:**
- `hcp` crea únicamente el *contenedor* vacío: `tfe_variable_set` +
  `tfe_project_variable_set` (esto ya estaba bien, no requirió cambios).
- `governance` es quien va a escribir los `tfe_variable` con los valores
  reales — porque es la única workspace con acceso a GCP en este punto de
  la cadena, y porque va a ser ella misma quien cree el WIF interno de
  cada proyecto (los referencia directo como atributos de sus propios
  `resource`, sin necesitar `data`). Para poder escribir en el variable set
  que `hcp` ya creó (que no le pertenece en su propio state),
  `governance` lo referencia con `data "tfe_variable_set"`, y necesita un
  segundo provider (`tfe`, además de `google`) con su propio `TFE_TOKEN`
  para poder hablar con la API de HCP Terraform.

Se evaluó también usar `data` para traer valores del proyecto **bootstrap**
hacia `governance` (en vez de a los proyectos dev/prod) — mismo problema:
`governance` necesita estar ya autenticado contra GCP para poder ejecutar
*cualquier* `data` block, así que no resuelve el huevo-y-gallina, solo lo
mueve un paso.

## 18. WIF del proyecto bootstrap — cuarta instancia del mismo patrón

Para que `governance-mgmt` pueda autenticarse contra GCP necesita el WIF
del proyecto bootstrap ya configurado — pero configurarlo con Terraform
requeriría que `governance-mgmt` ya tuviera esa autenticación, que es
justo lo que se está creando. Es la cuarta vez que aparece este patrón
exacto en el proyecto (org/proyecto/workspace de mgmt en el punto 4, el
team token en el punto 5, el proyecto semilla en sí en el punto 13): no se
puede usar una identidad automatizada para crear la identidad que esa
misma automatización necesita para existir.

**Resolución, igual que las tres veces anteriores:** un paso manual, con
`gcloud` y credenciales humanas. Se verificó contra el repositorio oficial
de ejemplos de HashiCorp (`terraform-dynamic-credentials-setup-examples`)
la sintaxis exacta antes de escribir el script — en particular el
`attribute-condition`, que restringe el provider a un `assertion.sub` con
`startsWith(...)`, no a atributos custom sueltos como se había asumido
antes de verificar.

Se creó `configs/seed-project-gcp/create-seed-wif.sh`, que dentro de
`excel-pipeline-seed`:
- Habilita las APIs necesarias (`iamcredentials`, `sts`).
- Crea el Workload Identity Pool y el Provider OIDC, con el
  `attribute-condition` acotado específicamente a la workspace
  `excel-pipeline-governance-mgmt` (nunca al pool completo ni a la
  organización de HCP Terraform entera).
- Crea la Service Account y le otorga los roles de Organización
  (`folderCreator`, `projectCreator`, `billing.user`).
- Otorga `workloadIdentityUser` sobre esa SA, restringido al pool — seguro
  porque solo un token que ya pasó el `attribute-condition` llega a poder
  usar ese binding.
- Imprime los 6 valores `TFC_GCP_*` para cargar a mano en
  `excel-pipeline-governance-mgmt`.

## 19. Secuencia completa de bootstrap, de punta a punta

Con todo lo anterior, la cadena manual → apply queda así (✅ hecho, ⏳
pendiente):

1. ✅ Manual — dominio, Cloud Identity, Organización de GCP.
2. ✅ Manual (`create-seed-project.sh`) — folders `bootstrap`/`shared` y
   sus proyectos `excel-pipeline-seed`/`excel-pipeline-shared`.
3. ✅ Manual — organización, proyecto mgmt y workspace `excel-pipeline-hcp-mgmt`
   en HCP Terraform; Team API Token (`owners`) y variables (`organization`,
   `vcs_repo_identifier`, `github_oauth_token_id`) cargadas ahí. La conexión
   VCS en sí también se creó a mano (ver punto 20) — no vía código.
4. ✅ Apply de `terraform/platform/hcp/` (en `hcp-mgmt`) — crea los
   proyectos HCP Terraform dev/prod, las 8 workspaces de dominio, la
   workspace `governance-mgmt` (las 9 usando la conexión VCS manual del
   punto 3), y los variable sets vacíos por proyecto.
5. ⏳ Manual (`create-seed-wif.sh`) — WIF pool/provider/SA dentro de
   `excel-pipeline-seed`, acotado a `governance-mgmt`.
6. ⏳ Manual — cargar los 6 `TFC_GCP_*` resultantes, más un `TFE_TOKEN`,
   como variables de `excel-pipeline-governance-mgmt`.
7. ⏳ Apply de `terraform/platform/governance/` (todavía sin escribir, en
   `governance-mgmt`) — crea los folders `development`/`production`, los
   proyectos `excel-pipeline-dev`/`-prod`, el WIF interno de cada uno, los
   bindings de IAM a grupos, y escribe esos valores en los variable sets
   que el paso 4 ya había creado.
8. A partir de acá, sin más pasos manuales: las 8 workspaces de dominio
   (ya creadas en el paso 4) pueden aplicar `terraform/domains/*` con
   credenciales reales.

## 20. `tfe_oauth_client` abandonado — conexión VCS creada a mano

El `tfe_oauth_client` con Personal Access Token (sección 8) tampoco terminó
funcionando: el apply falló porque el token usado no autenticaba
correctamente contra GitHub. Es la segunda vez que un método de conexión
VCS gestionado por código falla en la práctica — antes la GitHub App
(sección 8), ahora `tfe_oauth_client`.

**Resolución:** se eliminó `vcs.tf` por completo. En su lugar, se creó a
mano una conexión OAuth custom con GitHub a nivel organización, desde la UI
de HCP Terraform, y se toma su `oauth_token_id` (`ot-xxxxxxxx`) directo
como variable (`github_oauth_token_id`, sensible), sin ningún recurso
Terraform de por medio. Los 9 `vcs_repo` (8 workspaces de dominio +
`governance-mgmt`) la referencian con `var.github_oauth_token_id`.

**Por qué se dejó de insistir en gestionarlo por código:** a diferencia de
los otros bootstraps manuales de este proyecto (todos resuelven un
problema estructural de huevo-y-gallina, no evitable), acá no hay ningún
impedimento técnico para hacerlo con Terraform — simplemente, dos intentos
distintos de automatizarlo fallaron en la práctica, y crear la conexión
una sola vez a mano y referenciar su ID resultó más confiable que seguir
depurando por qué el camino automatizado no autenticaba. No todo beneficio
de "está en código" vale la pena perseguir cuando el costo de depurarlo
supera el de un paso manual documentado, sobre todo para algo que se
configura una única vez.

## 21. Scaffolding de `terraform/platform/governance/`, y `shared` sale del script manual

Se crearon los archivos vacíos de `terraform/platform/governance/`:
`terraform.tf`, `providers.tf`, `organization.tf`, `locals.tf`, `folders.tf`,
`projects.tf`, `iam.tf`, `wif.tf`, `variable_sets.tf`, `variables.tf`,
`outputs.tf` — separando por tipo de recurso, mismo criterio que en `hcp/`.

Al planear esto se notó que el folder `shared` y el proyecto
`excel-pipeline-shared` (mencionados como creados a mano en el punto 14)
nunca se llegaron a ejecutar — solo se corrió la parte del proyecto semilla.
Revisando el motivo original para crear `shared` a mano (mismo script que el
seed), no aplica: a diferencia del proyecto semilla, `shared` no aloja
ningún WIF que otra cosa necesite para poder arrancar — es un proyecto
normal, así que `governance` puede crearlo con el mismo `for_each` que usa
para `development`/`production`, una vez que ya tiene su propio WIF andando
(punto 18). Se corrigió el punto 14 para reflejar que nunca se creó, y se
recortó `create-seed-project.sh` (y su README) para que solo cree el folder
`bootstrap` y el proyecto semilla — el único que sí tiene el impedimento
estructural real.

Esto deja el bootstrap manual reducido a su mínimo genuino: un solo
proyecto de GCP creado a mano, no dos.

## 22. Renombre de las variables `organization`, y por qué no era un conflicto técnico

Surgió la duda de si `hcp/` y `governance/` podían tener cada uno una
variable llamada `organization` sin chocar, siendo que significan cosas
distintas (organización de HCP Terraform vs. Organización de GCP).
**Aclaración:** no hay conflicto técnico posible — cada directorio es un
root module aislado, aplicado por una workspace distinta, con su propio
state y sus propias variables cargadas. Terraform nunca evalúa ambos en el
mismo contexto. El motivo real para renombrar fue puramente de legibilidad
humana, no de corrección funcional.

Se renombró de todas formas, seguiendo la misma convención en los dos
lugares: `hcp/variables.tf` pasó de `organization` a `hcp_organization_name`
(propagado a `providers.tf`, `projects.tf`, `workspaces.tf`,
`variable_sets.tf` y `terraform.tfvars` local), y `governance/variables.tf`
usa `gcp_organization_id` para la Organización de GCP y también declara su
propio `hcp_organization_name` (mismo valor que en `hcp/`, porque
`governance` también necesita hablarle a la API de HCP Terraform para
escribir en los variable sets — ver punto 25).

## 23. Tabla de grupos de IAM — de 5 a 9, por una fuga entre entornos

Al pasar la tabla de grupos/roles a código se encontraron primero varias
inconsistencias puntuales en el borrador original que el usuario había
compartido: `api-runtime-sa` no debía tener `pubsub.subscriber` (la API
nunca consume Pub/Sub, solo el worker), faltaba un rol de GCS en dos
grupos, `ci-cd-pipelines@` tenía como miembro a `excel-client-sa` (la
identidad de "quien llama a la API", sin relación con construir imágenes),
e `infra-admins@` solo tenía 2 de los ~6 roles que en realidad necesita
para crear los 4 dominios.

Corregido eso, apareció un problema más de fondo: varios grupos
(`gke-workloads@`, `app-runtime@`, y la parte de SA de `infra-admins@`)
iban a contener Service Accounts que existen **una vez por proyecto**
(`worker-gke-sa` de dev es una identidad distinta a la de prod). Un solo
grupo compartido, atado a un recurso de dev y por separado a uno de prod,
filtra acceso — el worker de dev termina con permisos sobre el recurso de
prod, porque la membresía del grupo no distingue de qué proyecto es cada
miembro.

**Resolución:** grupos separados por entorno para las 4 categorías que
envuelven identidades por-proyecto (`gke-workloads-{env}@`,
`app-runtime-{env}@`, `infra-admins-{env}@`, `api-invokers-{env}@`) — 8
grupos. `ci-cd-pipelines@` queda como uno solo, porque apunta únicamente al
proyecto `shared`, sin límite de entorno que proteger. Total: 9 grupos.

Se documentó todo en `docs/governance/iam.md`, incluyendo por qué cada
binding vive en `governance` (solo los de `infra-admins-{env}@`, a nivel
proyecto) o en el domain correspondiente (el resto, a nivel recurso).

## 24. Primer código de `governance` — bugs en el borrador de `locals.tf`/`folders.tf`

El primer intento de `locals.tf`/`folders.tf` tenía varios errores:
- Confundía la convención de nombres de **folders** (`development`,
  `production` — nombre completo, sin prefijo) con la de **proyectos**
  (`excel-pipeline-dev` — prefijo corto). Es la única excepción a la
  convención corta, y se mezcló con la regla general por error.
- `keys(env)` sobre un elemento de un `for` que ya era un string (no un
  mapa) — error de tipo.
- `parent = var.organization` le pasaba al módulo de folders un nombre en
  vez del formato `"organizations/{ID}"` que espera.
- Se usaban `per_folder_admins`/`all_folder_admins` del módulo, que por
  defecto otorgan `roles/owner` a nivel folder — mucho más amplio que el
  modelo de permisos granulares por proyecto ya definido. Se optó por no
  usar el mecanismo de roles del módulo (`set_roles = false`) y manejar
  todos los bindings de `infra-admins-{env}@` aparte, en `iam.tf`.

Corregido, `locals.tf`/`folders.tf`/`projects.tf` quedaron escritos con un
único `local.projects` (mapa dev/prod/shared → folder + project id) del
que se derivan tanto los folders como los proyectos vía `for_each`.

## 25. WIF por proyecto (dev/prod), y publicación de credenciales hacia HCP Terraform

Implementado en código lo que se había diseñado en el punto 17: `wif.tf`
crea, para dev y prod, su propio Workload Identity Pool + Provider OIDC +
Service Account (`sa-terraform-deployer`) — identidad separada de la del
proyecto bootstrap, acotada únicamente a su propio proyecto. La SA no
recibe roles directamente en este archivo; los hereda por ser miembro de
`infra-admins-{env}@` (punto 23).

Una diferencia con el WIF del bootstrap (punto 18): ahí el
`attribute_condition` se acotaba a una sola workspace
(`excel-pipeline-governance-mgmt`). Acá se acota al **Project de HCP
Terraform** de ese entorno (`excel-processing-pipeline-gke-dev`, por
ejemplo) en vez de a una sola workspace, porque las 4 workspaces de
dominio de ese entorno comparten esta misma identidad.

`variable_sets.tf` completa el circuito: agrega el provider `tfe` (nuevo en
`governance`, además de `google`/`google-beta`), busca por nombre los
variable sets vacíos que `hcp` ya había creado
(`data "tfe_variable_set"`), y escribe ahí los 6 valores `TFC_GCP_*` por
entorno.

**Bug encontrado en el camino:** `issuer_uri` no es un atributo de primer
nivel en `google_iam_workload_identity_pool_provider` — va anidado en un
bloque `oidc { issuer_uri = ... }`. Lo marcó el linter del IDE, no una
revisión manual.

Con esto, el paso 7 de la secuencia de bootstrap (punto 19) queda escrito
en código — falta correrlo.

## 26. Revisión de seguridad de `governance/` completo

Pedido explícito de revisar todo el directorio en busca de vulnerabilidades,
bugs o algo potencialmente dañino, antes del primer apply real. Tres
hallazgos, los tres corregidos:

- `google_project_service` (`iamcredentials`, `sts` en `wif.tf`) tiene
  `disable_on_destroy = true` por defecto — destruir ese recurso (un
  `destroy` accidental, un refactor que saca el bloque) deshabilitaría la
  API activamente, rompiendo el auth WIF de las 4 workspaces de dominio de
  ese entorno. Se agregó `disable_on_destroy = false`.
- Los `tfe_variable` que escriben los `TFC_GCP_*` en los variable sets
  (`variable_sets.tf`) no estaban marcados `sensitive` — inconsistente con
  el mismo criterio ya aplicado a otros IDs del proyecto. Se agregó
  `sensitive = true`.
- Comparando el `attribute_condition` nuevo de `wif.tf` contra el viejo de
  `create-seed-wif.sh`, se encontró que este último terminaba sin `:` al
  final del nombre de la workspace — un `startsWith` sin delimitador final
  puede matchear por coincidencia de prefijo (`workspace-mgmt` matchea
  contra un futuro `workspace-mgmt-v2`). Se agregó el `:` final.

De paso se verificó (no hacía falta cambiar nada) que `google_project` ya
tiene `deletion_policy = "PREVENT"` por defecto desde el provider v6+, así
que los 3 proyectos ya estaban protegidos contra un destroy accidental sin
código adicional.

## 27. Conflicto de versión de providers en el primer `terraform init`

```
Error: Failed to query available provider packages
Could not retrieve the list of available versions for provider
hashicorp/google: no available releases match the given constraints
>= 3.67.0, >= 6.0.0, < 8.0.0, ~> 8.1
```

`governance/terraform.tf` fijaba `google`/`google-beta` en `~> 8.1` — pero
`terraform-google-modules/group/google` exige `< 8` internamente (ya
verificado meses atrás al evaluar ese módulo, sección de evaluación de
módulos). `>= 8.1` y `< 8` no tienen ninguna versión en común. El error solo
aparece en un `terraform init` real — ninguna revisión de código lo
detecta sin cruzar manualmente el `versions.tf` de cada módulo de terceros
contra el `required_providers` propio.

**Fix:** `~> 7.0` — satisface tanto el `< 8` del módulo de grupos como el
`>= 6.0.0` que pedía el módulo de folders.

## 28. Primeros plans reales: `TFE_TOKEN` faltante y límite de 127 bytes en WIF

Dos errores distintos en los primeros intentos de plan sobre
`governance-mgmt`:

**`could not find variable set tomas-navarro-projects/dev-credentials`** —
a pesar de que los variable sets sí existían (visibles en la UI). La causa
no era ausencia sino permisos: nunca se había cargado `TFE_TOKEN` en
`governance-mgmt` (quedó documentado en su README pero no se llegó a
cargar), así que el provider `tfe` usaba el token limitado que HCP
Terraform inyecta por defecto — el propio log lo advertía ("Authentication
method has limited TFE provider permissions"). Se evaluó (y descartó)
empujar `TFE_TOKEN` desde `hcp` con el mismo mecanismo usado para
`hcp_organization_name` — a diferencia de ese valor, `TFE_TOKEN` es un
credential real con poder de owner; duplicarlo en el state de `hcp` además
del de `governance` aumenta la exposición sin reducir ninguna carga manual
(igual hay que tipearlo una vez en algún lado). Se cargó directo en
`governance-mgmt`, igual que en `hcp-mgmt`.

**`google.subject exceeds the 127 bytes limit`** — al generar el token para
`governance-admin-sa@excel-pipeline-seed`. Límite real de GCP, no
documentado en la guía de setup de HCP Terraform (sí en la doc de
troubleshooting de IAM, verificada antes de aplicar el fix): el atributo
`google.subject` no puede superar 127 bytes, y estaba mapeado directo desde
`assertion.sub` — que con nombres tan descriptivos como los de este
proyecto (`excel-processing-pipeline-gke-mgmt`, `excel-pipeline-governance-mgmt`)
supera el límite. Importante: esto no afecta `attribute_condition`, que
sigue evaluando el `sub` completo sin restricción de tamaño — el límite es
específico del atributo *mapeado*, que solo se usa para identificar al
llamante en los audit logs.

**Fix:** mapear `google.subject` a `assertion.terraform_workspace_id` (corto
y ya único) en vez de al `sub` completo — aplicado en `wif.tf` y en
`create-seed-wif.sh`. Como el provider del bootstrap ya existía (creado en
una corrida anterior), hizo falta un `gcloud ... providers update-oidc`
manual además del cambio de código — crear de nuevo no alcanza porque el
script salta la creación si ya existe.

## 29. Ciclo circular por mal diagnóstico del "quota project"

Al resolver un error de "Cloud Resource Manager API no habilitada", el
primer intento habilitó `cloudresourcemanager`/`cloudidentity` **sobre los
proyectos dev/prod**, con un `depends_on` del módulo de folders hacia esa
habilitación. Resultado: un ciclo real — `google_project.this` depende del
folder (`folder_id`), el folder ahora depende de la API-en-el-proyecto, y
la API se habilita sobre un proyecto (dev/prod) que depende a su vez de que
el folder ya exista.

**El diagnóstico de fondo estaba mal apuntado.** La pregunta correcta con
un error de API no habilitada en GCP no es "¿sobre qué recurso estoy
operando?", sino "¿cuál es el *quota project* de la identidad que hace la
llamada?". Las llamadas que fallaban (buscar la organización, crear
folders) las hace `governance-admin-sa`, cuyo proyecto de origen es
`excel-pipeline-seed` — dev/prod ni siquiera existen todavía en ese punto
de la secuencia, así que habilitar algo sobre ellos no podía resolver nada.

**Fix:** se revirtieron los dos `google_project_service` y sus `depends_on`
en `governance`, y se agregaron `cloudresourcemanager.googleapis.com` y
`cloudidentity.googleapis.com` al `gcloud services enable` que ya existía
en `create-seed-wif.sh`, sobre el proyecto semilla — mismo lugar donde ya
se habilitaban `iamcredentials`/`sts`.

## 30. Un valor sensible no puede ser clave de un `for_each`

Con lo anterior resuelto, apareció un error nuevo dentro del módulo de
grupos:

```
Error: Invalid for_each argument
var.members is list of string with 2 elements
Sensitive values, or values derived from sensitive values, cannot be
used as for_each arguments.
```

El módulo `terraform-google-group` arma internamente un
`google_cloud_identity_group_membership` por miembro, usando el email de
cada uno como clave del `for_each`. Terraform prohíbe categóricamente que
una clave de `for_each`/`count` provenga de un valor `sensitive` — la clave
queda expuesta en las direcciones de los recursos del state, y ahí no hay
forma de redactarla. `personal_account_email` (marcada `sensitive`) rompía
esto en las dos instancias de `infra-admins-{env}@`.

**Fix:** `nonsensitive(var.personal_account_email)` solo en el punto donde
se arma la lista de miembros — no se le sacó el flag `sensitive` a la
variable en su declaración, así que sigue protegida en cualquier otro uso
futuro. No era un secreto real de por sí; el flag era higiene contra
hardcodearlo, algo que cargarlo como variable de workspace ya cubre por su
cuenta, con o sin el flag.

## 31. Primer apply real — folders creados, y el permiso que ningún IAM binding otorga

Con todo lo anterior resuelto, el primer `apply` real llegó bastante más
lejos: los folders `development` y `production` se crearon con éxito.
Aparecieron dos problemas nuevos:

**El folder `shared` ya existía** — quedó de un intento manual anterior que
no se había limpiado (ver punto 21, donde se documentó que ese folder nunca
se llegó a crear... resultó que sí, parcialmente, y no se detectó a tiempo).
GCP no permite dos folders con el mismo nombre bajo el mismo padre. Sin
código que arreglar acá — solo hacía falta borrar el folder viejo a mano
antes de reintentar. Los folders que sí se crearon en este apply quedan en
el state, no hace falta recrearlos.

**Las 9 Cloud Identity Groups fallaron con `Error 403: Permission denied`**,
a pesar de que `governance-admin-sa` ya tenía `folderCreator`,
`projectCreator` y `billing.user` a nivel Organización. La hipótesis inicial
fue que faltaba `roles/resourcemanager.organizationViewer` — descartada al
verificar: ese rol es para acceso de un humano a la Consola, un contexto
distinto.

**La causa real, verificada contra la documentación oficial de Cloud
Identity:** administrar Google Groups **no se autoriza por Cloud IAM en
absoluto** — es un sistema de autorización separado, propio de la consola
de administración de Google Workspace. Ningún `gcloud organizations
add-iam-policy-binding` resuelve esto, sin importar qué rol se otorgue. La
única forma es asignar el rol de administrador **"Groups Admin"** a la
Service Account directamente desde `admin.google.com` (requiere acceso de
Super Admin de Workspace) — un paso manual que ningún script de este
proyecto puede cubrir, porque la API de administración de Workspace es un
sistema aparte del que gestiona Terraform.

Se documentó como prerequisito en `configs/seed-project-gcp/README.md` y
`governance/README.md`, en vez de intentar resolverlo con más código.

## 32. El rol de Groups Admin funcionó — y aparecieron dos problemas más

Con el rol asignado, las 9 groups se crearon con éxito. Dos problemas
nuevos, distintos entre sí:

**Los 3 `google_project` fallaron por Cloud Billing API.**
`failed to check permissions on billing account ...: Cloud Billing API has
not been used in project 910394319354`. Exactamente el mismo patrón de
"quota project" del punto 29: crear un proyecto con una cuenta de
facturación asociada requiere `cloudbilling.googleapis.com` habilitada en
el proyecto **que hace la llamada** (el proyecto semilla), no en el
proyecto que se está creando. Se agregó `cloudbilling.googleapis.com` al
mismo `gcloud services enable` de `create-seed-wif.sh` que ya tenía las
otras tres APIs de "quota project".

**Todas las membresías de Service Account fallaron**, menos las dos de la
cuenta personal. El mensaje — `Permission denied ... or it may not exist`
— fue la pista: no era un problema de permisos nuevo, sino que
`worker-gke-sa`, `api-runtime-sa`, `excel-client-sa` y
`cloudbuild-deployer-sa` **todavía no existen en GCP** — ningún código las
crea todavía, están reservadas para cuando se escriban `terraform/domains/gke`
y `terraform/domains/cloud-run`. (`sa-terraform-deployer` también falló en
esta corrida, pero por una razón distinta y ya resuelta: dependía del
proyecto, que falló por el billing de arriba.)

**Fix:** se aplicó el mismo criterio de "quien crea el recurso lo agrega al
grupo" que ya regía para los roles (punto 17). `governance` deja de
intentar agregar esos 4 miembros — `gke-workloads-{env}@`,
`app-runtime-{env}@`, `api-invokers-{env}@` y `ci-cd-pipelines@` quedan
creados pero **vacíos** hasta que el domain correspondiente cree su SA y
la agregue (con `data "google_cloud_identity_group"`, sin re-declarar el
grupo). `infra-admins-{env}@` es la única excepción — `sa-terraform-deployer`
sí la crea `governance` en `wif.tf`, así que su membresía se queda ahí.

## 33. Los 3 proyectos ya se crean bien — y aparece una quinta API, más un bug real de dependencia

Con `cloudbilling` habilitada, los 3 proyectos (`excel-pipeline-dev/prod/shared`)
se crearon con éxito por primera vez. Dos problemas nuevos:

**Falta `iam.googleapis.com` en el proyecto semilla** — mismo patrón de
quota project de siempre (puntos 29, 32): crear una Service Account o un
Workload Identity Pool para dev/prod requiere esa API habilitada en el
proyecto que hace la llamada. Se agregó al mismo `gcloud services enable`
de `create-seed-wif.sh` (ya van cinco APIs ahí: `iamcredentials`, `sts`,
`cloudresourcemanager`, `cloudidentity`, `cloudbilling`, `iam`).

**Bug real, no solo un permiso faltante:** comparando los timestamps del
log, la membresía de `sa-terraform-deployer` intentó crearse a las
`15:09:42` — **28 segundos antes** de que `google_service_account.deployer["dev"]`
empezara siquiera a crearse (`15:10:10`). En `locals.tf`, el email de esa
SA se armaba con interpolación de string
(`"${...}@${...}.iam.gserviceaccount.com"`) en vez de referenciar el
recurso real. Un string armado a mano no genera una dependencia en el
grafo de Terraform — el provider quedó libre de ejecutar la membresía y la
creación de la SA en cualquier orden, sin garantía de cuál va primero. Es
el mismo error que ya se había corregido una vez en `wif.tf` (ahí se
referenciaba `google_iam_workload_identity_pool.deployer[...].name` en vez
de reconstruir el path a mano) — se coló de nuevo en un lugar distinto.

**Fix:** `google_service_account.deployer[pair[1]].email` en vez del
string interpolado. Se revisó el resto de `governance/` en busca del mismo
patrón (`grep` por emails armados con interpolación) — no apareció en
ningún otro lado.

## 34. Diseño del dominio `registry/shared`: Cloud Build nativo, y `data` vs `tfe_outputs`

Al planear cómo construir imágenes y publicarlas en Artifact Registry, surgieron
dos decisiones de diseño independientes.

**Opción A vs Opción B para CI:** se evaluó GitHub Actions con WIF propio
(Opción B) contra Cloud Build 2nd-gen autenticado directamente contra GitHub
(Opción A, `google_cloudbuildv2_connection`). Se eligió la **Opción A**: evita
mantener un segundo mecanismo de identidad federada aparte del que ya se usa
para HCP Terraform, y los triggers se crean por código una vez resuelta la
conexión manual — mismo patrón ya aceptado en la sección 20 para la conexión
VCS de HCP Terraform (un paso manual de autorización, el resto en Terraform).

**`data` vs `tfe_outputs` para compartir datos entre configuraciones de
Terraform:** se investigó (documentación oficial + artículos) para asentar el
criterio, hasta ahora aplicado de forma intuitiva sin haberlo verificado
explícitamente. Conclusión:
- `data` blocks: solo para recursos que **ninguna** configuración de Terraform
  de este proyecto gestiona — ya sea porque son externos (`data
  "google_organization"`) o porque pertenecen a un state ajeno cuyo objeto en
  sí no es el output de interés, sino su existencia (`data "tfe_project"
  "mgmt"`, para ubicar workspaces nuevas ahí sin importar ese proyecto al
  propio state — ver sección 15).
- `tfe_outputs`: para leer valores de **salida** de una workspace hermana que
  sí gestiona el recurso con Terraform — el caso de uso real y todavía
  pendiente es `gke` leyendo el ID de la VPC/subnet que crea `networking`.

El patrón ya en uso en el proyecto resultó correcto sin cambios; esta
investigación solo lo deja documentado con criterio explícito para no tener
que redecidirlo cada vez que aparezca un caso nuevo.

## 35. Extensión de `hcp` y `governance` para el proyecto `shared`

Con el diseño anterior resuelto, se extendió el código ya existente en vez de
crear una estructura paralela:

- **`hcp/`**: `tfe_project.shared` (standalone, fuera del `for_each` de
  dev/prod — solo aloja una workspace, no el patrón domain×entorno completo),
  `tfe_workspace.registry` (`working_directory =
  "terraform/domains/registry/shared"`), y un `tfe_variable_set.shared_credentials`
  + `tfe_project_variable_set` standalone, mismo mecanismo que ya existía para
  dev/prod (sección 11).
- **`governance/`**: se extendió `local.deployer_environments` para incluir
  `"shared"` — el WIF genérico de `wif.tf` (pool/provider/SA por proyecto, ver
  sección 25) no necesitó ningún cambio de lógica, solo el nuevo elemento en
  el set de entornos. Se agregó el grupo `registry-admins@` (`sa-terraform-deployer`
  del proyecto shared como único miembro) con sus 4 roles de proyecto
  (`artifactregistry.admin`, `cloudbuild.connectionAdmin`,
  `cloudbuild.builds.editor`, `iam.serviceAccountAdmin`) — un grupo distinto de
  `ci-cd-pipelines@` (que sigue reservado para `cloudbuild-deployer-sa`, la
  identidad que corre los *builds*, no la que aplica Terraform sobre ese
  dominio).

Ambos applies (`hcp-mgmt` y `governance-mgmt`) corrieron sin errores nuevos.

## 36. La conexión OAuth GitHub↔HCP Terraform se rompió sola, y una hipótesis descartada

Al crear `tfe_workspace.registry` (sección 35), el apply falló con
`"Repository doesn't exist or isn't accessible"` sobre el mismo repo que las
otras 9 workspaces ya venían usando sin problema desde la conexión manual de
la sección 20.

**Hipótesis inicial, descartada:** que fuera un delay de propagación por
tratarse de un proyecto (`shared`) recién creado. No era eso — el proyecto
nuevo no tiene ninguna relación con qué conexiones VCS están disponibles a
nivel organización, y las otras workspaces del mismo proyecto no mostraban
ningún síntoma de estar "esperando" nada.

**Causa real:** la conexión OAuth con GitHub, que llevaba semanas funcionando
sin tocarse, se había desconectado del lado de GitHub — no por expiración
normal de token, sino una desconexión efectiva de la integración instalada.
**Fix:** reinstalar/reautorizar la OAuth application desde el lado de HCP
Terraform (Organization Settings → VCS Providers). Una vez reautorizada, el
apply de `tfe_workspace.registry` funcionó sin cambiar nada del código.

---

## Lecciones aprendidas

- **Generar credenciales externas al principio, no sobre la marcha.** El
  problema más grande de esta etapa (sección 8) fue no haber generado el
  Personal Access Token de GitHub y cargado la variable de Terraform en HCP
  Terraform *antes* de empezar a escribir `workspaces.tf`. Se probaron en
  orden: GitHub App → intento de arreglar su scope → confusión con el token
  personal de HCP Terraform → recién ahí, `tfe_oauth_client` con PAT clásico.
  Si el PAT se hubiera generado al principio (al mismo tiempo que se decidió
  "vamos a conectar por VCS"), se hubiera evitado toda la vuelta con la
  GitHub App. **Para el próximo proyecto:** cuando una integración externa
  requiere un credential (token, key, connection ID), generarlo y validarlo
  *antes* de escribir el código que lo consume, no después.
- **Distinguir "ID de referencia" de "secreto real" antes de decidir dónde
  vive una variable.** Varias confusiones de esta etapa (Team Token vs
  Organization Token vs `terraform login`; variable set vs variable directa)
  se resolvieron preguntando primero "¿cuántas cosas consumen este valor?" y
  "¿qué pasa si esto se filtra?" antes de elegir el mecanismo de HCP
  Terraform para guardarlo.
- **Un mismo texto en la UI puede referirse a objetos completamente
  distintos según el contexto** (el "token" de HCP Terraform vs. el PAT de
  GitHub; "environment variable" vs. "Terraform variable"). Cuando algo no
  cierra, vale la pena describir literalmente lo que se ve en pantalla en vez
  de asumir a qué concepto corresponde.
- **Verificar contra documentación oficial los nombres exactos de una
  integración externa, en vez de confiar en la memoria.** Al listar las
  variables de dynamic credentials para GCP apareció una faltante
  (`TFC_GCP_PRINCIPAL_TYPE`) que no se había mencionado antes. Un nombre de
  variable mal recordado no rompe en el momento de escribir el código — rompe
  en silencio en el primer run, con un error de autenticación difícil de
  distinguir de un problema de permisos real.
- **No todo vale la pena gestionarlo por código.** La conexión VCS
  (sección 20) es el único bootstrap manual de este proyecto que no
  responde a un problema estructural de huevo-y-gallina — se podría haber
  seguido depurando por qué `tfe_oauth_client` no autenticaba. Después de
  dos intentos fallidos (GitHub App, luego `tfe_oauth_client`), crear la
  conexión una vez a mano y referenciar su ID resultó más confiable que
  perseguir el ideal de "todo en Terraform" para algo que se configura una
  única vez y no vuelve a tocarse.
- **Un grupo de IAM no hereda el aislamiento de sus miembros.** El diseño
  ya separaba dev y prod en proyectos, WIF y workspaces distintas — pero al
  meter Service Accounts por-proyecto dentro de un grupo *compartido*
  (sección 23), ese aislamiento se rompía igual, porque la membresía de un
  Cloud Identity group es global, no sabe a qué entorno "pertenece" cada
  miembro. La lección: cuando un identificador agrupa identidades que en
  el resto del sistema están deliberadamente separadas, hay que preguntarse
  explícitamente si el agrupador en sí también necesita esa separación —
  no alcanza con que las piezas de abajo estén bien aisladas.
- **Un plan fallido no es lo mismo que un apply fallido.** Las secciones 27
  a 30 son cuatro errores reales seguidos en los primeros intentos de
  aplicar `governance` — conflicto de versiones de provider, token
  faltante, un límite de 127 bytes no documentado en la guía principal de
  GCP, un ciclo por mal diagnóstico de "quota project", una restricción del
  lenguaje sobre valores sensibles. Ninguno tocó infraestructura real: un
  `plan` que falla es inerte, no deja nada a medio crear. La mayoría de
  estos son del tipo que solo aparece corriendo contra la API real, no
  revisando código con cuidado — no hay forma realista de anticiparlos
  todos de antemano sin haber pisado ya este terreno antes.
- **Verificar el constraint de un módulo una vez no alcanza — hay que
  volver a cruzarlo cada vez que se toca el archivo que lo declara.** El
  conflicto de versión de la sección 27 pasó porque el `< 8` del módulo de
  grupos ya se había verificado meses antes (al evaluarlo por primera vez),
  pero no se volvió a cruzar al escribir `governance/terraform.tf` después
  — se repitió el mismo `~> 8.1` que se había usado en `hcp/`, donde no
  aplicaba esa restricción. Haber verificado algo una vez no lo vuelve
  válido para siempre en un archivo distinto.
- **No todo problema de permisos en GCP se resuelve con un IAM binding.**
  La sección 31 es el ejemplo más claro de todo el proyecto: por más roles
  de Cloud IAM que tuviera `governance-admin-sa` a nivel Organización,
  ninguno le daba permiso para crear Cloud Identity Groups, porque ese
  producto se autoriza desde un sistema completamente aparte (el Admin
  Console de Google Workspace). Antes de asumir "necesito otro rol de IAM"
  frente a un 403, vale la pena confirmar que el recurso en cuestión
  efectivamente vive bajo el paraguas de Cloud IAM — no todos los productos
  de Google lo hacen.
- **"Permission denied ... or it may not exist" a veces significa
  literalmente eso: no existe.** En la sección 32, el error de las
  membresías de grupo parecía uno más de permisos — pero la causa real era
  que las Service Accounts referenciadas todavía no estaban creadas en
  ningún código. El principio de "quien crea el recurso es quien lo
  vincula" (ya aplicado a los roles en el punto 17) también aplica a la
  membresía de grupos, y por la misma razón: `governance` no debería
  intentar gestionar la pertenencia de una identidad que no le pertenece
  ni que ella misma crea.
- **Un identificador armado con interpolación de string nunca genera una
  dependencia — solo una referencia directa al recurso lo hace.** Pasó dos
  veces en este proyecto con el mismo tipo de error (`wif.tf` y, en la
  sección 33, `locals.tf`): escribir `"${a}@${b}.dominio.com"` en vez de
  `recurso.atributo` compila igual y en apariencia "funciona" en el plan,
  pero Terraform no tiene forma de saber que ese string depende de que otro
  recurso exista primero — el orden de ejecución queda librado al azar. La
  regla práctica: si un valor *podría* obtenerse de un atributo de un
  `resource` que ya está en el código, usar ese atributo — nunca
  reconstruir el mismo dato a mano, aunque el resultado sea idéntico.
- **No confiar en el pattern-matching contra un problema anterior parecido
  sin verificar la causa real.** En la sección 36, el error de la workspace
  `registry` se parecía superficialmente a "recurso recién creado, todavía no
  propagado" — pero la causa era otra por completo (una integración externa
  que se había desconectado del lado de GitHub, sin relación con qué proyecto
  de HCP Terraform era nuevo). Una hipótesis que "suena plausible" por
  parecerse a un caso previo puede llevar a descartar la investigación real
  demasiado pronto.
