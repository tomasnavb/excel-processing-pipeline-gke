# Architecture Diagram Style Guide — GCP

Conventions for drawing architecture diagrams for this project: what nests
inside what, colors, borders, naming, typography, icons, and how connections
are drawn. Keeping every diagram consistent with this guide means anyone
looking at one can read the others the same way.

---

## 1. Structure — what nests, and what doesn't

**Core rule:** the network diagram starts at **Project**, not at
Organization. Org and Folder are shown as lightweight context outside the
diagram — never as containers wrapped around the VPC.

```
Breadcrumb (outside the diagram, in the title):
tomasnavarro.dev → {folder-name} → excel-processing-pipeline-gke-{environment}

Network diagram (the diagram itself):
Project                                    ← outer border
  └── VPC
        └── Subnet (region)
              └── Zone (dotted border, no fill)
                    └── Resource icons (no background of their own)
```

Four levels of colored nesting. Never more than that.

---

## 2. Color Palette

> **Note:** Google does not publish an official color standard for
> container boxes (VPC, Subnet, Project, etc.) — the only system Google
> does standardize and document is the color of the **product icons**
> themselves. What follows is a consistent, project-specific convention —
> not an official one.

| Level | Hex | Usage |
|---|---|---|
| Project | `#e3f2fd` | Outer border of the network diagram |
| VPC | `#e6f4ea` | Green — **Networking** family |
| Subnet | `#ceead6` | Green, one shade darker than VPC (shows nesting) — **Networking** family |
| GKE Cluster | `#f3e5f5` | Purple — **Compute** family, deliberately distinct from the networking green |
| Zone / Region | *(no fill)* | Dotted border only — it's an annotation, not a container |

### Family rule — so the system scales without one-off decisions

Every resource category gets its own hue, and anything new added later joins
the family it belongs to — never an invented color per box:

| Family | Hue | What belongs here |
|---|---|---|
| **Networking** | Green | VPC, Subnet, and later: Cloud NAT, firewall rules, Cloud Router |
| **Compute** | Purple | GKE Cluster, and later: Compute Engine, node pools |

If a third category ever shows up (e.g. a "Data" box grouping Firestore +
GCS), give it a new hue that isn't already in use — never reuse green or
purple for anything outside networking/compute respectively.

**Reference only — not used in the network diagram, but used in the
governance tree diagram:**

| Level | Hex |
|---|---|
| Organization | `#eeebea` |
| Folder | `#fef7e0` |

---

## 3. Borders — compensating for pastel fills

| Level | Border width | Style |
|---|---|---|
| Project | 2px | Solid |
| VPC | 1.5px | Solid |
| Subnet | 1px | Solid |
| GKE Cluster | 1px | Solid |
| Zone / Region | 1px | **Dotted** |

The further out, the thicker the line — hierarchy should read from line
weight, not color alone.

---

## 4. Naming Convention

Follows the same pattern already used in Terraform:
**`[project]-[component]-[environment]`**, lowercase, hyphens only (never
underscores — GCP rejects them on several resource types, so hyphens
everywhere keeps it consistent).

> **Important:** `excel-processing-pipeline-gke` works fine as a repo/
> conceptual project name, but it's **too long for a real Project ID** —
> GCP caps Project ID at 30 characters, and `excel-processing-pipeline-gke-dev`
> is already 34. A short form is needed for the real ID.

| Resource | Pattern | Example (dev) | Example (prod) |
|---|---|---|---|
| Folder | `{environment}` | `development` | `production` |
| Project ID | `{short-project}-{environment}` | `excel-pipeline-dev` | `excel-pipeline-prod` |
| VPC | `{short-project}-vpc-{environment}` | `excel-pipeline-vpc-dev` | `excel-pipeline-vpc-prod` |
| Subnet | `{component}-subnet-{environment}-{region}` | `gke-subnet-dev-europe-west9` | `gke-subnet-prod-europe-west9` |
| GKE Cluster | `{short-project}-gke-{environment}` | `excel-pipeline-gke-dev` | `excel-pipeline-gke-prod` |
| Cloud Run service | `{short-project}-api-{environment}` | `excel-pipeline-api-dev` | `excel-pipeline-api-prod` |
| GCS bucket | `{project-id}-jobs` | `excel-pipeline-dev-jobs` | `excel-pipeline-prod-jobs` |
| Pub/Sub topic | `{short-project}-jobs-topic-{environment}` | `excel-pipeline-jobs-topic-dev` | `excel-pipeline-jobs-topic-prod` |
| Pub/Sub subscription | `{short-project}-jobs-sub-{environment}` | `excel-pipeline-jobs-sub-dev` | `excel-pipeline-jobs-sub-prod` |
| Artifact Registry | `{short-project}-images` *(no environment suffix — it's shared)* | `excel-pipeline-images` | *(same one)* |
| Service Account | `{purpose}-sa` | `worker-gke-sa`, `api-runtime-sa`, `excel-client-sa` | *(same names, one separate set per project — never shared between dev/prod)* |

### General rules, no exceptions

- **Always lowercase.** GCP rejects uppercase on most resource identifiers —
  better to bake that into the convention from the start.
- **`dev`/`prod` stay `dev`/`prod`, never mixed with `development`/
  `production`.** The one exception is the Folder name, where
  `development`/`production` reads better as an organizational category and
  isn't competing with any character limit.
- **Region goes at the end of the name, only for regional resources**
  (subnets — not VPCs, which are global).
- **GCS bucket names are unique globally across all of GCP, not just within
  your project** — that's why the full Project ID belongs in the bucket
  name instead of just `jobs`, to avoid colliding with someone else's bucket
  anywhere in the world.
- **Service accounts never carry an environment suffix**
  (`worker-gke-sa`, not `worker-gke-sa-dev`) — isolation already comes from
  each project (dev/prod) having its own copy of that service account, same
  short name, living in a different project.

---

## 5. Typography

| Element | Font | Size | Weight |
|---|---|---|---|
| Diagram title | Google Sans (or Roboto) | 20-22pt | Bold |
| Container name (Project/VPC/Subnet) | Google Sans / Roboto | 13-14pt | Bold |
| Resource name (under each icon) | Roboto | 10-11pt | Regular |
| Annotations (region, config, "prod only" notes) | Roboto | 9pt | Italic, gray `#5f6368` |

---

## 6. Icons

- Always official GCP icons, never with a custom fill color added — they
  already ship with their own category color (Google redesigned the whole
  icon system in early 2025, going from 250+ icons down to ~40, grouped by
  category; this guide doesn't specify a color per category because Google
  doesn't publish those hex values — every icon already comes with its own).
- Always download from `cloud.google.com/icons` (the current 2025 set),
  never reuse old icons saved from another project — they may be deprecated.
- Uniform size across icons in the same diagram — never stretched to "fill
  space."
- Text label always below the icon, never overlaid on top of it.
- **GKE Cluster:** a single icon represents the cluster, never stacked — the
  cluster is a singular resource, it doesn't "scale" as a concept. To show
  that the *worker pods* scale, use a text annotation
  (`"Worker pods — autoscale 2-10 replicas"`), not stacked icons — save
  stacked visuals for a diagram dedicated specifically to the cluster's
  internal behavior, if one is ever needed.

---

## 7. Lines & Connections

> Same caveat as the color palette: this is **not an official Google
> standard** — it's a widely used architecture-diagramming convention (not
> GCP-specific), adopted here as a consistent project convention.

### When to use each line type

| Relationship type | Line style | Weight | Arrowhead |
|---|---|---|---|
| **Hierarchy / ownership** (Org→Folder→Project, or Project→VPC→Subnet) | Solid, right-angle (elbow) | Thin (1px) | No arrowhead, or a small neutral one — it's "contains," not "acts on" |
| **Real data flow** (a call, an event, something that actually happens at runtime) | Solid | Medium (1.5-2px) | Simple arrowhead, pointing in the direction of **whoever initiates the call** (not "where the data goes") |
| **Read-only / reference relationship** (e.g. a project that only *reads* from a shared Artifact Registry) | **Dotted** | Thin (1px) | Arrowhead, with the label clarifying "read-only" |
| **Dependency without direct data flow** (e.g. "this must exist before that," but they don't talk to each other at runtime) | Dotted | Thin (1px) | No arrowhead, or an open one |

### The direction rule — the most important one in this section

The arrowhead **always** points from the caller to the callee — it never
tries to represent "which way the data travels." A database that's read from
and written to (e.g. GKE ↔ Firestore) still gets **one single arrow**,
GKE → Firestore, because Firestore never initiates the connection — it only
responds. Never use bidirectional arrows unless the relationship is
genuinely symmetric (real bidirectional streaming, like a WebSocket/gRPC
stream) — which a database or a normal REST API call is not.

```
❌ GKE ↔ Firestore              (implies both sides initiate — false)
✅ GKE → Firestore  "reads/updates job state"   (GKE is always the caller)
```

### Quick decision rule

- **Is it one box containing another?** → hierarchy line (solid, thin, low
  visual priority).
- **Does one service actually call another at runtime?** → flow line
  (solid, arrowhead from the caller, labeled with what happens:
  `"uploads file"`, `"OBJECT_FINALIZE"`, `"pull (worker)"`, `"reads/updates
  state"`).
- **Is the relationship "I can see/use this but don't own or modify it"?**
  → dotted, always with the "read-only" label.

### Line color

- Hierarchy lines: neutral gray (`#9aa0a6`) — shouldn't compete visually
  with the data flow, which is the point of the diagram.
- Data flow lines: dark gray (`#5f6368`) or black — maximum contrast, it's
  the first thing the eye should follow.
- Dotted lines (read-only / reference): same gray as flow lines — the
  dotted style already distinguishes them, no need to also change the
  color.

### What to avoid

- No "decorative" line colors without meaning (a red line shouldn't exist
  unless you genuinely want to flag something critical or an error path).
- No curved/organic lines — in technical diagrams, straight or right-angle
  (elbow) lines read better and avoid confusing crossings.
- Never leave a line unlabeled when it connects two services that
  communicate — the method/event/protocol name is what turns an arrow into
  actual information.
- Never use bidirectional arrows to represent read+write — this is the most
  common mistake, and it already has its own dedicated rule above.

---

## 8. Pre-publish checklist

- [ ] Are Org/Folder outside the nesting (breadcrumb or separate tree)?
- [ ] Does the network diagram have 4 levels max (Project → VPC → Subnet → Zone)?
- [ ] Does the Zone have a dotted border and no fill, instead of another colored box?
- [ ] Do container colors follow the palette in section 2 (remembering it's a project convention, not an official one)?
- [ ] Does every resource follow the naming convention in section 4 (lowercase, hyphens, `[project]-[component]-[environment]`)?
- [ ] Are the icons the current version from `cloud.google.com/icons`, with no added fill?
- [ ] Are hierarchy lines and data-flow lines clearly distinct (weight + color, not just intuition)?
- [ ] Is every "read-only" relationship dotted and labeled as such?
- [ ] Does every data-flow arrow have a label explaining what happens, pointing from whoever INITIATES the call?
- [ ] Is no arrow bidirectional unless the relationship is genuinely symmetric?
