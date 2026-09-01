# excel-processing-pipeline-gke

Proyecto de portfolio para transición hacia roles de Cloud Infrastructure/DevOps
(GCP + Docker + Terraform). El usuario ya tiene HashiCorp Terraform Associate (004)
y Google Cloud ACE, y su próximo objetivo es la certificación CKA.

## Qué hace el proyecto

Pipeline de procesamiento asíncrono de archivos Excel sobre GCP:

- Una API en **FastAPI**, desplegada en **Cloud Run**, recibe el archivo, lo valida,
  lo sube a GCS, y guarda un registro de estado en **Firestore** (con el `job_id`
  como ID del documento).
- GCS notifica **nativamente** a **Pub/Sub** cuando el objeto termina de subirse
  (`OBJECT_FINALIZE`) — la API **nunca** publica el mensaje manualmente, para evitar
  el dual-write problem.
- Un **worker en GKE** consume el mensaje, extrae el `job_id` del path del objeto,
  busca el contexto de negocio en Firestore, procesa el archivo, sube el resultado
  a GCS, y actualiza el estado.
- Autenticación de "quien llama" a la API vía **Service Account + IAM**
  (`roles/run.invoker`), sin base de datos de usuarios propia.
- Infra gestionada con **HCP Terraform**, usando **Workload Identity Federation**
  para autenticación sin keys estáticas.
- **Dev y prod son proyectos de GCP completamente separados** (no solo VPCs
  distintas) — aislamiento real de IAM, cuotas y billing. Cada uno vive bajo su
  propio **Folder** dentro de una **Organization** (Cloud Identity Free, dominio
  propio).
- Permisos de IAM otorgados a **grupos de Cloud Identity**, nunca a Service
  Accounts individuales — para demostrar el patrón de RBAC correcto, no bindings
  sueltos.
- Región: **europe-west9 (Paris)**.

## Estructura de carpetas — respetar tal cual, no reorganizar sin preguntar

```
excel-processing-pipeline-gke/
├── api/                      # FastAPI (Cloud Run)
├── processor/                # Worker (GKE)
├── configs/                  # Manifiestos K8s (Kustomize: base/ + overlays/dev,prod)
├── cloudbuild/                # Triggers y pipelines de Cloud Build
├── docs/
└── terraform/
    ├── modules/               # Código reutilizable — SIN provider blocks adentro
    │   ├── networking/
    │   ├── gke/
    │   ├── cloud-run/
    │   └── ...
    ├── domains/               # Infra REAL de GCP, separada por dominio funcional
    │   ├── networking/{dev,prod}/
    │   ├── gke/{dev,prod}/
    │   ├── data/{dev,prod}/         # Firestore, GCS, Pub/Sub
    │   └── cloud-run/{dev,prod}/
    └── platform/              # META — no toca recursos de GCP directo
        ├── hcp/               # tfe_workspace, tfe_project, tfe_variable_set
        └── governance/        # google_cloud_identity_group, IAM a nivel org/folder
```

## Convención de nombres — obligatoria, sin excepciones

Patrón base: `{proyecto-corto}-{componente}-{entorno}`, siempre minúsculas, siempre
guiones (nunca guiones bajos en nombres de recursos GCP).

- **Nombre corto del proyecto:** `excel-pipeline` (el nombre completo
  `excel-processing-pipeline-gke` excede el límite de 30 caracteres de un Project
  ID de GCP — nunca usarlo para IDs reales).
- Project ID: `excel-pipeline-{dev|prod}`
- VPC: `excel-pipeline-vpc-{dev|prod}`
- Subred: `gke-subnet-{dev|prod}-europe-west9`
- GKE Cluster: `excel-pipeline-gke-{dev|prod}`
- Cloud Run service: `excel-pipeline-api-{dev|prod}`
- GCS bucket: `excel-pipeline-{dev|prod}-jobs` (nombres de bucket son únicos a nivel
  global de GCP)
- Pub/Sub topic/sub: `excel-pipeline-jobs-topic-{dev|prod}` /
  `excel-pipeline-jobs-sub-{dev|prod}`
- Artifact Registry: `excel-pipeline-images` (compartido, sin sufijo de entorno)
- Service Accounts: `{propósito}-sa`, sin sufijo de entorno (`worker-gke-sa`,
  `api-runtime-sa`, `excel-client-sa`) — el aislamiento ya lo da que cada proyecto
  tenga su propia copia.
- Firestore usa la base `(default)` de cada proyecto — no crear bases con ID custom
  salvo pedido explícito.

## Cómo trabajar en este repo — lo más importante

El usuario está en transición de carrera y necesita **aprender**, no solo tener el
repo terminado.

**Generar directamente, sin pedir permiso paso a paso:**
- Scaffolding — estructura de carpetas, `main.tf`/`variables.tf`/`outputs.tf`
  boilerplate, `.gitignore`, templates de `cloudbuild.yaml`.
- Terraform de infraestructura "clásica" ya dominada: networking (VPC/subredes),
  IAM bindings, providers, backends.
- Cosas mecánicas y repetitivas: `tfe_workspace` para cada combinación
  domain×entorno una vez definido el patrón, aplicar la convención de nombres de
  forma consistente.

**NO generar código completo — explicar el enfoque y dejar que lo escriba el
usuario:**
- Todo lo relacionado a **Kubernetes/GKE** (manifiestos, Deployments, Services,
  Workload Identity de GKE, HPA) — territorio nuevo, en preparación para CKA.
- Decisiones de **diseño de arquitectura** — el usuario las razona, Claude actúa
  como sparring, no como quien decide.
- Cualquier código que el usuario vaya a explicar en una entrevista técnica — si no
  puede explicarlo línea por línea sin volver a mirarlo, no debería estar en el
  repo sin que él lo haya escrito o entendido a fondo primero.

Ante la duda sobre en qué bucket cae algo, preguntar antes de generar código
extenso — prefiere que lo frenen una vez de más a recibir 200 líneas de K8s que
después no sepa explicar.

## Documentos de referencia pendientes

El usuario tiene una guía de estética para diagramas de arquitectura (colores,
líneas, convenciones visuales) y una tabla de grupos/roles de IAM ya definida —
las va a pasar aparte cuando se trabaje en diagramas o en governance/IAM.
