# Mesh to Housing

**Mesh to Housing** is a framework for converting complex 3D models into sparse spatial guides that can be reconstructed inside game housing systems with strict object-count and API constraints.

The core problem is independent of any particular game: given a detailed 3D model and a limited point budget, determine which points best preserve its **geometry and visually important features**.

The resulting sparse representation can then be translated into different games through separate integration layers.

---

## Overview

```text
3D model
   │
   ▼
Mesh / point-cloud processing
   │
   ├── important-feature detection
   ├── manual anchor points
   └── geometry-aware sparsification
   │
   ▼
Sparse N-point representation
   │
   ▼
Game-independent guide
   │
   ├── ESO integration
   ├── WoW integration
   └── other game adapters
   │
   ▼
In-game construction guide
```

The geometry-processing pipeline is kept separate from game-specific integrations.

---

## Current Prototype

An early end-to-end prototype has already been tested in **The Elder Scrolls Online**.

The current workflow demonstrates:

- conversion of a 3D model into a point-based representation;
- CV-assisted detection of important features;
- manual refinement of selected points;
- sparsification of the remaining geometry;
- transfer of the resulting guide into the game;
- manual reconstruction using that guide.

### Face example

| Source mesh | CV-assisted feature selection | Sparse guide |
| --- | --- | --- |
| ![](assets/prototype/face_mesh_full.png) | ![](assets/prototype/face_mesh_CV.png) | ![](assets/prototype/face_mesh_sparse.png) |

| In-game guide | Reconstruction in progress | Finished build |
| --- | --- | --- |
| ![](assets/prototype/face_mesh_ESO.png) | ![](assets/prototype/face_mesh_eso_progress.png) | ![](assets/prototype/face_mesh_eso_final.png) |

### Dragon example

A second prototype applies the same general workflow to different geometry.

| Sparse guide | Guide transferred in-game | Finished build |
| --- | --- | --- |
| ![](assets/prototype/dragon_mesh.png) | ![](assets/prototype/dragon_start.png) | ![](assets/prototype/dragon_full.png) |

The original notebook code used for these experiments is not included in the repository. The current project is intended to turn the prototype into a general and reproducible pipeline.

---

## Core Problem

Standard downsampling can preserve overall surface coverage while losing features that are disproportionately important for reconstruction.

At a fixed point budget, the representation needs to balance:

- geometric coverage;
- important local features;
- manually selected anchors;
- structural properties relevant to the model.

If important points are selected manually or through feature detection, the remaining point budget should be sampled **with those points already taken into account**, rather than generating an independent sparse representation and adding them afterwards.


---

## Planned Methods

Methods will be compared at identical target point counts.

### Geometric baselines

Standard methods such as **uniform sampling, farthest-point sampling, and mesh simplification** will provide reference baselines for geometry-only reduction.

### Feature-aware sampling

Important points can be fixed before the remaining geometry is sparsified.

They may come from:

- manual anchor selection;
- geometric or mesh saliency;
- CV-assisted landmark detection;
- learned feature-selection methods where useful.

The remaining points will then be selected while accounting for those existing anchors, allowing the available point budget to be distributed more effectively over the rest of the model.

### Topology-aware analysis

For models with meaningful connected components, loops, or cavities, the project will also investigate **Topological Data Analysis (TDA)** as an additional evaluation and sampling signal.

Persistent homology can be used to test whether significant topological structures survive reduction and, where useful, whether this information can improve point selection.

---

## Game Integration

The core pipeline outputs a game-independent set of spatial guide points.

Depending on the capabilities of a particular game, these can be represented in two main ways.

### Direct visualization

Where addon APIs support custom 3D visualization, the guide can be displayed directly in-game as points or markers positioned at the generated coordinates.

### Object-based representation

Where direct visualization is not available, in-game objects can be placed at the guide coordinates to represent the sparse model.

Different objects, colors, or markers may also be used to distinguish automatically selected points from important feature or anchor points.

Initial target environments are:

- **The Elder Scrolls Online Housing**
- **World of Warcraft Housing**

Additional games can be supported through separate adapters without changing the core geometry pipeline.

---

## Evaluation

Reduction methods will be compared at the same point budgets using three main criteria:

- **Geometric fidelity** — how well the sparse representation covers the original shape;
- **Feature preservation** — whether important automatic and manually selected features remain represented;
- **Topology preservation** — where relevant, whether significant structural properties survive reduction.

A small reference model set will be included for reproducible comparisons, while the pipeline will also support user-provided 3D models.