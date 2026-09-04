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

## 14. Setup inicial de los proyectos bootstrap y shared de GCP

Con el dominio comprado, Cloud Identity activada y la Organización ya creada
(prerequisito que había quedado bloqueado en el punto 13), se crearon a mano
dos folders con un propósito bien distinto cada uno, en vez de agrupar todo
en un único folder de "gestión":

- **`bootstrap`**, con el proyecto semilla (`excel-pipeline-seed`) adentro:
  aloja únicamente el Workload Identity Pool/Provider y la Service Account
  que Terraform va a impersonar para gestionar el resto de la organización
  (folders, proyectos dev/prod). Es un "root of trust" — sostiene permisos a
  nivel Organización, así que conviene mantenerlo aislado y de bajo tráfico
  para que sea fácil de auditar.
- **`shared`**, con el proyecto `excel-pipeline-shared` adentro: aloja
  recursos compartidos entre dev y prod — el primer caso concreto es
  Artifact Registry (`excel-pipeline-images`), para poder construir una
  imagen una sola vez y promoverla entre entornos sin duplicarla. Se decidió
  como proyecto aparte (ni dev, ni prod, ni el de bootstrap) para no romper
  el aislamiento entre dev/prod, y para no mezclar un recurso de tráfico
  constante con el proyecto más sensible del setup.

Ninguno de los dos aloja carga de trabajo de la aplicación.

Pasos ejecutados — variables de entorno con valores de ejemplo, después la
secuencia de comandos:

```bash
# Variables de entorno (valores de ejemplo — reemplazar por los propios)
export ORG_ID="123456789012"
export ADMIN_USER="admin@example.dev"
export BOOTSTRAP_FOLDER_NAME="bootstrap"
export SEED_PROJECT_ID="excel-pipeline-seed"
export SHARED_FOLDER_NAME="shared"
export SHARED_PROJECT_ID="excel-pipeline-shared"
export REGION="europe-west9"

# Otorgar al usuario administrador permiso para crear folders a nivel
# organización (necesario antes de poder crear los folders)
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

# --- Folder shared + proyecto compartido ---
SHARED_FOLDER_NAME_FULL=$(gcloud resource-manager folders create \
  --display-name="$SHARED_FOLDER_NAME" \
  --organization="$ORG_ID" \
  --format="value(name)")
SHARED_FOLDER_ID="${SHARED_FOLDER_NAME_FULL#folders/}"

gcloud projects create "$SHARED_PROJECT_ID" \
  --folder="$SHARED_FOLDER_ID" \
  --name="excel-pipeline-shared-project" \
  --labels=type=shared-project

# Crear una configuración de gcloud CLI dedicada para el proyecto semilla,
# para no operar accidentalmente sobre otro proyecto/contexto
gcloud config configurations create excel-pipeline-seed
gcloud config set project "$SEED_PROJECT_ID"
gcloud config set compute/region "$REGION"

# Verificar
gcloud config configurations describe excel-pipeline-seed
```

Quedan pendientes: sobre el proyecto semilla, crear el Workload Identity
Pool + Provider, la Service Account que Terraform va a impersonar, y los
bindings de IAM a nivel Organización descritos en el punto 13; sobre el
proyecto shared, crear el propio Artifact Registry y los bindings de IAM
cross-project que le den lectura a los service accounts de GKE en dev y
prod.

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
