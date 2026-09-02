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

## 14. Setup inicial del proyecto semilla (seed project) de GCP

Con el dominio comprado, Cloud Identity activada y la Organización ya creada
(prerequisito que había quedado bloqueado en el punto 13), se creó a mano el
proyecto semilla descrito en ese mismo punto: el único propósito de este
proyecto es alojar más adelante el Workload Identity Pool/Provider y la
Service Account que Terraform va a impersonar para gestionar el resto de la
organización (folders, proyectos dev/prod). No aloja ninguna carga de
trabajo de la aplicación.

Pasos ejecutados — variables de entorno con valores de ejemplo, después la
secuencia de comandos:

```bash
# Variables de entorno (valores de ejemplo — reemplazar por los propios)
export ORG_ID="123456789012"
export ADMIN_USER="admin@example.dev"
export SEED_FOLDER_NAME="seed-projects"
export SEED_PROJECT_ID="excel-pipeline-seed"
export REGION="europe-west9"

# Otorgar al usuario administrador permiso para crear folders a nivel
# organización (necesario antes de poder crear el folder semilla)
gcloud organizations add-iam-policy-binding "$ORG_ID" \
  --member="user:$ADMIN_USER" \
  --role="roles/resourcemanager.folderAdmin"

# Crear un folder dedicado para alojar el proyecto semilla
gcloud resource-manager folders create \
  --display-name="$SEED_FOLDER_NAME" \
  --organization="$ORG_ID"

# Tomar el folder ID devuelto por el comando anterior
export SEED_FOLDER_ID="<folder-id-obtenido-arriba>"

# Crear el proyecto semilla dentro de ese folder
gcloud projects create "$SEED_PROJECT_ID" \
  --folder="$SEED_FOLDER_ID" \
  --name="excel-pipeline-seed-project" \
  --labels=type=seed-project

# Crear una configuración de gcloud CLI dedicada, para no operar
# accidentalmente sobre otro proyecto/contexto
gcloud config configurations create excel-pipeline-seed
gcloud config set project "$SEED_PROJECT_ID"
gcloud config set compute/region "$REGION"

# Verificar
gcloud config configurations describe excel-pipeline-seed
```

Quedan pendientes, sobre este mismo proyecto: crear el Workload Identity
Pool + Provider, la Service Account que Terraform va a impersonar, y los
bindings de IAM a nivel Organización descritos en el punto 13.

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
