# Mesh to Housing

Tools for translating complex 3D models into sparse construction guides
for in-game housing systems with strict object-count constraints.

The goal is to preserve the recognizable structure of a model while
reducing it to a practical number of guide points that can be recreated
using in-game furniture or building objects.

## Status

Early development.

## Initial goals

- Import and preprocess 3D meshes
- Generate point-cloud representations
- Reduce meshes to a configurable number of guide points
- Allow users to manually preserve important focal points
- Visualize and export the resulting construction guide

Later development will explore topology-aware simplification,
visual saliency, and ML-assisted point selection.

## Early proof of concept

I first tested the core idea in a small notebook prototype.

This example shows the process:
1. a sparse mesh / guide-point representation
2. that mesh transferred in-game
3. the finished build, which I created manually using those guide points

| Mesh / guide points | Mesh transferred in-game | Finished manual build |
| --- | --- | --- |
| ![](assets/prototype/dragon_mesh.png) | ![](assets/prototype/dragon_start.png) | ![](assets/prototype/dragon_full.png) |

*These images are from an earlier prototype. The notebook code is not included in this repository.*

## Planned integrations

- World of Warcraft Housing
- The Elder Scrolls Online Housing
